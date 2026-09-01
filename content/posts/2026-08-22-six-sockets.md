---
title: "Six sockets: a live-reload leak in two acts"
description: "A click stalled for 55 seconds while the server answered in 3 milliseconds. Debugging the browser's six-connection limit, abandoned SSE streams, and two fixes in Elixir."
tags: [personal, elixir, otp, oss, realtime]
---

Late one night I clicked a link on a `cherry serve` site and the browser just sat there. Fifty-five seconds. Then the page appeared instantly, as if nothing had happened. The same waterfall that recorded the freeze showed the server answering in under three milliseconds. Working out how both could be true turned into two bug fixes across two projects and a small tour of how BEAM processes and TCP sockets actually talk to each other. The full devlog is on the Cherry blog; here is the shape of it.

The 55 seconds sat in "Stalled", which is time the browser spent before it even tried to connect. The request wasn't slow; it was never sent. A performance trace named the culprit: every page served in dev opens a server-sent-events stream for live reload, nothing ever closed it, and navigating away puts the page in the back/forward cache with its stream still open. SSE over HTTP/1.1 counts against the browser's limit of six connections per host. Six cached pages, six held slots, and the next click queues until the browser evicts one. Production never shows this because HTTPS means HTTP/2, which multiplexes; local dev is plain HTTP, which means six.

Act one was Cherry's own handler, a `receive` with one clause and no `after`. The only way it learned the browser had gone was a failed write, and it only wrote when a rebuild happened. The fix in 0.4.1 is a heartbeat (`after heartbeat_ms -> chunk(conn, ": ping\n\n")`) and a client that closes its `EventSource` on `pagehide`. The write is the detector: a dead socket fails it.

Act two was cherrypicker, my dev proxy, which had made the same mistake one hop along and left twenty-one sockets in `CLOSE_WAIT`. Its handler was stuck inside a synchronous `Finch.stream`, so it could hear nothing else. The fix inverts the architecture: the upstream pull moves into a monitored reader process that forwards events as messages, and the handler puts the client socket in `active: :once` so the browser's departure arrives in its mailbox as `{:tcp_closed, _}`. Killing the reader releases the upstream connection for free, because Finch's pool monitors whoever checked the connection out. There is no cleanup code, because the runtime is the cleanup code.

The rule underneath both fixes: every way your wait can end must have a wake-up path, and a timeout is the wake-up path of last resort. The full post has the trace, the diagrams, the regression test and the exception-safety loose end that surfaced after it shipped: [Six sockets, on cherrybomb.dev](https://cherrybomb.dev/six-sockets/).
