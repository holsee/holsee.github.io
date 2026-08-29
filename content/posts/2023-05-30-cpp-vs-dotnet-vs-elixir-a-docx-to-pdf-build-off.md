---
title: "Driving a .NET PDF engine from the BEAM"
description: "A conversion library only exists for .NET, and the service that needs it is Elixir. A long-running .NET daemon on a Unix domain socket speaking JSON, an Elixir client, and a stress harness as the acceptance gate."
tags: [work, dotnet, elixir, bake-off]
draft: true
---

Seven weeks ago I opened three repositories to answer one question, and closed one of them before lunch. That's my favourite outcome of the whole spike, so let's start there.

## the question

We convert DOCX to PDF in a couple of places at work, and the fidelity of the open-source converter we'd been using wasn't good enough: tables in particular came out wrong in ways customers notice. The candidate replacement is a commercial document library whose native home is .NET. So the question was never "which library", it was "how does the BEAM talk to a .NET library", and I wanted the answer with evidence rather than opinion. One repo per route, and let the commits decide.

## day one: C++ is out

The first repo has three commits, all from the same morning. The library's vendor offers no native C++ build, only a cross-compiled version of the .NET one, which trails the .NET release and brings its own baggage. So the C++ route was rejected the same day it was opened, and the README says why. The point of that repo was to be able to say *why*, with evidence, rather than to have an opinion about C++.

## a daemon on a socket

The .NET repo had a working conversion, a Docker image and vendored fonts by the end of its first day, and grew into something production-shaped over the following weeks. The design that matters is how it's driven.

The BEAM doesn't need HTTP to talk to a local process. A long-running .NET daemon listens on a Unix domain socket and speaks a JSON request/response protocol: a request names an operation (convert this DOCX, fix these table widths, merge these PDFs) and a response carries a status and the processing time. No port to manage, no TLS to configure, no network surface at all: the socket is a file, the kernel enforces who can open it, and the sidecar lives and dies with the container.

```json
{"operation": "docx_to_pdf", "input": "/data/in/report.docx", "output": "/data/out/report.pdf"}
{"status": "ok", "processing_ms": 412}
```

On the Elixir side, `:gen_tcp` opens Unix sockets as readily as network ones (`:gen_tcp.connect({:local, path}, 0, [...])`), so the client is a small module that connects, writes a JSON line, and reads one back. The daemon is the unit of deployment; the Elixir side is a client. If you've ever wired two runtimes together with a REST API on localhost, this is the same idea with less of everything.

The daemon publishes as a self-contained build (ReadyToRun for Linux and macOS, x64 and arm64) so the container doesn't need a .NET runtime installed, and the fonts are vendored into the image with an explicit font path, because CJK rendering is the thing most likely to go quietly wrong inside a Linux container with no fonts, and the shared test corpus included Japanese documents.

## the harness is the acceptance gate

The third repo is the Elixir client, and the reason it's its own repo is the second thing in it: a configurable stress-test harness. Set the number of requests and the concurrency, point it at the socket, and it reports throughput and output sizes.

A converter that produces beautiful PDFs but falls over under concurrent requests from a BEAM node is not a converter we can deploy. The daemon had to pass the harness before it counted as done. Make the acceptance gate a harness, not a screenshot.

## where it's gone

The engine and the client went into the application that needed them as git subtrees, replacing a pipeline that had been patching table formatting in Python before handing off to the old converter. A subtree rather than a sidecar the app hopes is running: the conversion engine became part of the tree.

## if you're doing this

When the library you need lives in another runtime, a daemon on a Unix socket with a line-oriented JSON protocol is the smallest honest boundary: one process per container, one file to connect to, and nothing listening on the network. Give each route its own repo so the loser stays in the tree as evidence. And write the harness before you declare victory. Seven weeks, three languages, one daemon, one harness, and a same-day "no" I can still point at.
