---
title: "Streaming zip downloads straight from S3"
description: "Forty files live in S3 and the user wants one zip. Spool them to a temp file and the disk becomes the feature. Instead: a manifest of presigned URLs in, a signed link out, and the archive assembled chunk by chunk while the client downloads it, plus a decision to make about what happens when file 37 fails after the 200 has gone."
tags: [work, elixir, otp, phoenix, api-design, aws]
draft: true
---

"Download all" is a menace of a button. Behind it sits a folder's worth of files that live in S3, and the obvious implementation is grim: pull every file to the app server, write a zip to disk, serve the zip. The disk fills up, and the proxy times out while you spool. So the next obvious implementation adds a job queue, a notification for when the zip is ready, a cleanup task for the leftovers, and an apology in the UI in the meantime. A button has become infrastructure. At work I've just shipped a third option: a small Elixir service that assembles the zip while the client downloads it. The first byte arrives straight away and memory stays flat, because there is no archive on the server, only the chunk currently in flight.

The clever part is a library called [packmatic](https://hex.pm/packages/packmatic) by [Evadne Wu](https://github.com/evadne/packmatic). You hand it a manifest of entries (a URL to fetch from, a path inside the archive) and it gives you an Elixir `Stream` that emits a Zip64 archive in chunks as it is consumed. My contribution is the service around it, the operational wrapper that turns "these forty S3 objects" into a link anyone can click. The zip encoding, which is the hard bit, is Evadne's work, and it's excellent. Go read the design rationale in her README even if you never ship a zip in your life.

## The archive is assembled as it leaves

Zip turns out to be a friendly format to stream. Entries go first, each with a local header and its compressed bytes, and the index (the central directory) goes at the end, so you can be sending entry one before you've downloaded entry two. Packmatic wraps this in an encoder state machine inside `Stream.resource/3` (Elixir's lazy streams produce values only as a consumer pulls them, and `Stream.resource/3` builds one from an init, next and cleanup function, so the encoder runs exactly as fast as the socket drains): each time the connection wants another chunk, the encoder pulls the next chunk of the current source over HTTP, deflates it through a single zlib stream, and hands it on. Source downloads advance one chunk at a time, so a slow client slows the S3 fetches down rather than filling memory. On the service side, the entire streaming path is this:

```elixir
# apps/packmatic_app/lib/packmatic_app.ex
@spec send_chunked!(Plug.Conn.t(), package()) :: Plug.Conn.t()
def send_chunked!(conn, package) do
  %{package_name: package_name, manifest: manifest} = package

  manifest
  |> Packmatic.build_stream(on_error: :skip)
  |> Packmatic.Conn.send_chunked(conn, "#{package_name}.zip")
end
```

The entries are presigned S3 URLs, so the service holds no bucket credentials at all; the authority to read each file travels inside the manifest. And nothing accumulates: per entry the encoder keeps only the bookkeeping the central directory will need (offset, CRC-32, sizes), a handful of integers and a path. Archives larger than the host's disk are fine. Individual files over 4GB are fine too, which is what the Zip64 format is for.

## Everything that can fail early, fails early

The API is two requests. You POST a manifest and get back a signed link; someone GETs the link and the bytes flow. In between, the manifest sits in a little process with a time to live (five minutes by default, a day at the most), after which the link quietly dies. Each package is a process started on demand under a DynamicSupervisor and found by reference through a Registry, with a timer that stops it when the TTL passes; expiry is the process exiting, and there's no cleanup job.

That split is doing deliberate work. A chunked response commits you: the moment the first byte goes out you have already said `200 OK`, and there's no second status line to send. So every check that can fail politely is pushed in front of that moment. A malformed manifest is rejected at submission with a 422 and a JSON pointer to the offending field. At download time the reference is verified and the package looked up before any body bytes move:

```elixir
# apps/packmatic_web/lib/packmatic_web/controllers/packages_controller.ex
def download_package(conn, %{ref: package_reference}) do
  with {:ok, %{"pkg" => package_id}} <- PackageReference.verify(package_reference),
       {:ok, package} <- PackmaticApp.package(package_id) do
    PackmaticApp.send_chunked!(conn, package)
  else
    {:error, :signature_error} ->
      conn
      |> put_status(401)
      |> json(%{message: "Unauthorised"})

    {:error, :not_found} ->
      conn
      |> put_status(404)
      |> json(%{message: "Not Found"})
  end
end
```

## Entry 37 fails after the 200

Now the awkward one. The archive has forty entries, and entry 37's presigned URL has expired, or S3 resets the connection halfway through. Part of entry 37 may already be on the wire, inside a response that already promised success. What do you tell the client? Nothing. HTTP gives you no way to say "actually, that went badly" once a chunked body is under way.

Packmatic offers two policies. With `on_error: :halt` the stream raises and the connection drops, leaving the client a truncated file that won't open, which is at least visibly wrong. With `on_error: :skip` it carries on, and the failed entry is left out when the central directory is journaled at the end:

```elixir
# evadne/packmatic lib/packmatic/encoder.ex
defp stream_encode_error(reason, %{current: {entry, _, _}, on_error: :skip} = state) do
  state = %{state | current: nil, encoded: [{entry, {:error, reason}} | state.encoded]}
  stream_emit([], :encoding, state)
end
# ...
defp stream_journal(%{current: nil, remaining: [{_, {:error, _}} | rest]} = state) do
  stream_journal(%{state | remaining: rest})
end
```

Zip readers navigate by the central directory, so the half-sent bytes become unreferenced junk inside the file and extraction quietly yields 39 files. We run `:skip`: for bulk downloads of submitted coursework, 39 files and a gap beats an archive that won't open, and the missing one can be requested again. But be clear-eyed about the trade: the client cannot detect the gap from the HTTP layer, because the response is a 200 and the zip is valid. If your domain can't wear that, you need a side channel, perhaps a manifest file written into the archive itself. We're running the library's in-progress error-reporting branch so that, at minimum, the server knows exactly which entries failed and why. The reverse failure is covered as well: when the client disconnects, `Plug.Conn.chunk/2` returns `{:error, :closed}` and packmatic halts the stream, so abandoned downloads stop fetching from S3.

## The transferable bits

Two habits and an opinion. When the product asks for "download all", reach for a fold over remote sources before you reach for a temp file, because the temp file is where the disk-space incident, the cleanup job and the proxy timeout all live. Any stack with lazy streams and chunked responses can play; the BEAM just makes it pleasant.

Second, sort your failure modes by when they can still be reported. Everything that can fail before the first byte should do so loudly, with a proper status code. For whatever remains, choose a policy on purpose (visibly broken, or silently partial) and write it down, because the protocol will refuse to choose for you.

And the opinion: a thin service over someone else's well-designed library is a perfectly good service. The value I added is validation, signed references, TTLs and supervision. The hard part is packmatic, and the right thing to do about that is say so, loudly, and send people to it.

## Where to look

- packmatic on Hex: https://hex.pm/packages/packmatic
- packmatic source and design rationale: https://github.com/evadne/packmatic
