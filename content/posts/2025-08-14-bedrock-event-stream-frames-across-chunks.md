---
title: "Two frames in one chunk: decoding Bedrock's event stream"
description: "Two PRs to ex_aws_bedrock: decoding AWS event-stream frames that arrive split across HTTP chunks, and verifying the CRC32s the frames carry. Binary pattern matching doing what it's for."
tags: [personal, elixir, aws, llm, oss]
draft: true
---

The second of two pull requests I sent to `ex_aws_bedrock` merged today, so here's the pair of them together, because they're a nice small lesson in reading a binary protocol properly with Elixir. I hit the bug in a production system at work that streams Bedrock responses; the fix is upstream, under my own name, in a library I don't own.

## The symptom

Stream a long response from a model on Bedrock and, some of the time, the decoder hands you garbage. Short responses were fine. Long ones fell apart somewhere in the middle. Classic "works in the demo" bug.

Bedrock doesn't speak server-sent events. It speaks AWS's binary event-stream format: a sequence of framed messages, each one self-describing. A frame looks like this on the wire:

```text
total length   (uint32) ┐
headers length (uint32) ├─ prelude, 12 bytes
prelude CRC32 (uint32) ┘
headers        (headers length bytes)
payload        (total − headers − 16 bytes)
message CRC32 (uint32)
```

The library's decoder, when I got to it, assumed one HTTP chunk was one frame:

```elixir
# lib/ex_aws/bedrock/event_stream.ex, before
def decode_chunk(data) do
  with <<
         message_total_length::32,
         headers_length::32,
         _prelude_checksum::32,
         _headers::binary-size(headers_length),
         body::binary-size(message_total_length - headers_length - 16),
         _message_checksum::32
       >> <- data,
       {:ok, %{"bytes" => bytes}} <- Jason.decode(body),
       # ...
```

That's a lovely bit of binary pattern matching. It's also exactly one frame. HTTP chunking doesn't care about frame boundaries, so the moment Bedrock packed two events into a chunk, the match consumed the first and silently dropped the second. Which is why long streams lost words in the middle and short ones were fine: short answers fit in one frame.

## Fix one: decode until the bytes run out

The change (PR #37, merged October 2024) is small and the shape of it is the point. `decode_chunk/1` now returns a *list*, and the stream is built with `flat_map` instead of `map`:

```elixir
-      Stream.map(stream, &decode_chunk/1)
+      Stream.flat_map(stream, &decode_chunk/1)
```

and the decoder recurses over the binary, peeling a frame at a time:

```elixir
defp decode_chunks(<<>>, acc), do: Enum.reverse(acc)

defp decode_chunks(data, acc) do
  case parse_chunk(data) do
    {:ok, chunk, rest} ->
      decode_chunks(rest, [{:chunk, chunk} | acc])

    {:error, reason, rest} ->
      decode_chunks(rest, [{:bad_chunk, data, reason} | acc])

    :incomplete ->
      # May wish to buffer incomplete data
      [{:incomplete_chunk, data} | acc]
  end
end
```

`parse_chunk/1` does the actual match, guarded by the size it read from the prelude, and hands back `rest` so the recursion can carry on:

```elixir
defp parse_chunk(
       <<
         message_total_length::unsigned-32,
         headers_length::unsigned-32,
         _prelude_checksum::unsigned-32,
         _headers::binary-size(headers_length),
         rest::binary
       >> = data
     )
     when byte_size(data) >= message_total_length do
  message_length = message_total_length - @message_overhead
  body_length = message_length - headers_length

  if byte_size(rest) >= body_length + @checksum_size do
    <<body::binary-size(body_length), _message_checksum::unsigned-32, next_data::binary>> = rest
    # ... decode body, return {:ok, chunk, next_data}
  else
    :incomplete
  end
end
```

Three things I'd point at. The guard `byte_size(data) >= message_total_length` is the whole difference between "one frame" and "as many frames as are here". The magic `16` became named attributes (`@prelude_length`, `@message_overhead`), because a number in a binary pattern is a number you'll get wrong later. And `:incomplete` is reported rather than raised, with a comment admitting the honest gap: a frame split *across* chunks still needs buffering at the stream level, and this PR doesn't do that. It fixes the case that was eating words; the boundary case is flagged, not hidden.

The test is the bug in miniature: a real multi-chunk Claude response captured as a binary, asserting two chunks come out where one used to.

## Fix two: check the checksums

Every frame carries two CRC32s and the old decoder threw both away. That's fine until it isn't: a corrupted frame decodes into a plausible-looking wrong payload, and you'd never know. PR #38, merged today, verifies both:

```elixir
prelude = <<message_total_length::unsigned-32, headers_length::unsigned-32>>

with :ok <- verify_prelude_checksum(prelude, prelude_checksum),
     :ok <- verify_message_checksum(prelude, prelude_checksum, headers, body, message_checksum),
     {:ok, chunk} <- process_chunk(body) do
  {:ok, chunk, next_data}
else
  {:error, reason} -> {:error, reason, next_data}
end
```

The message checksum covers the prelude, the prelude's own checksum, the headers and the body, in that order, and the implementation is one line of standard library:

```elixir
defp crc32(data), do: :erlang.crc32(data)
```

Erlang has had CRC32 in the runtime since forever. There's no dependency to add, and a bad frame now comes back as `{:bad_chunk, data, :invalid_message_checksum}` instead of as a wrong answer. Tests cover a bad prelude checksum, a bad message checksum and a truncated frame.

## The awkward part

The last version of the library published to hex is 2.5.1, from January 2024. Neither fix is in a release. Everyone streaming Bedrock through the hex package is still on the one-frame-per-chunk decoder, and I'm running production on a git dependency pointed at the fork. A merged fix that isn't released is, for most people, not a fix. I'll keep nudging.

If you take one thing from this: when you pattern-match a binary protocol, the guard on total length is not optional, and `Stream.flat_map` is the honest signature for "one input, zero or more outputs". The rest is `:erlang.crc32/1`.

## Where to look

- PR #37, multi-chunk decoding: https://github.com/devstopfix/ex_aws_bedrock/pull/37 (merged 2024-10-08)
- PR #38, CRC32 verification: https://github.com/devstopfix/ex_aws_bedrock/pull/38 (merged 2025-08-14)
- hex: `ex_aws_bedrock`, last release 2.5.1 (2024-01-14) at the time of writing.
