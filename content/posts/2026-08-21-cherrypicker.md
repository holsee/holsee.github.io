---
title: "cherrypicker: names for your ports"
description: "Why we built a pure-Elixir alternative to portless in a day, how the register model works, and what cherry serve --name will do with it in the next release."
tags: [personal, elixir, oss, static-site, security]
draft: true
---

`localhost:4000` means nothing. `localhost:5173` means nothing. Six dev servers into an afternoon, the one you bookmarked yesterday is someone else now. Vercel's portless named this problem properly: dev servers should live at stable named URLs like `http://docs.localhost`, and the port lottery should be the proxy's problem. I wanted that for Cherry. I didn't want it enough to install it.

portless is a global npm install that self-elevates to bind port 443 and installs a locally trusted root certificate authority, then wraps your dev server as a child process and injects the right port flag for each framework it recognises. Each of those is defensible alone; together they are a lot of blast radius for a convenience tool sitting in the most attacked package ecosystem there is. So I built [cherrypicker](https://github.com/holsee/cherrypicker) in a day: the same idea, on the BEAM, with the opposite instincts. Two runtime dependencies, no Node, no certificate authority, no process wrapping.

The design bet is one sentence: apps register, nothing gets wrapped.

```text
$ cherrypicker route docs 8080
http://docs.localhost
```

The daemon is a loopback reverse proxy reading the `Host` header: `docs.localhost` looks up `docs` in an ETS table and streams the request to `127.0.0.1:8080`. Names resolve for free because `*.localhost` already points at loopback on every major OS. Discovery is a file, not configuration: the daemon writes its bound port to `~/.cherrypicker/daemon.json`, and a client that finds no daemon gets `{:error, :no_daemon}` and carries on with plain port URLs. Degradation is a designed path.

Cherry itself takes no dependency on cherrypicker. `cherry serve --name mysite` speaks the four-endpoint control API through eighty lines of standard library, registers its port if a daemon is running, and falls back to the port URL if not. The contract is small enough not to need a library, which was the point.

The full post, with the streaming details that keep live reload working through the proxy: [cherrypicker, on cherrybomb.dev](https://cherrybomb.dev/cherrypicker/).
