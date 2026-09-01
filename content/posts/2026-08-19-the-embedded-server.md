---
title: "The embedded server"
description: "How cherry serve works inside. Bandit, a Registry as the whole pubsub, server-sent events, and a file watcher that refuses to lie."
tags: [personal, elixir, otp, oss, static-site]
---

Cherry's output is aggressively static: plain files, no runtime, deploy anywhere. But `cherry serve`, the dev loop, is the one place it runs long-lived processes, and it's a nice little tour of why the BEAM is such a pleasant place to build tools. The full walk through the code is on the Cherry blog; here's what's in it.

The whole thing is three supervised children. Bandit serves the built `_site/`. A `Registry` (the standard library's process directory) is the entire pubsub for live reload. A `GenServer` (a process with state and a mailbox) watches your files. `one_for_one` supervision means a crashing watcher never takes the web server down: you lose live reload for a moment while it restarts, and your browser tab never notices.

Live reload needs exactly one message, "the site was rebuilt", and you don't need a broker for that:

```elixir
def broadcast do
  Registry.dispatch(@registry, :reload, fn entries ->
    for {pid, _value} <- entries, do: send(pid, :cherry_reload)
  end)
end
```

Every open page holds a server-sent-events connection that subscribes and waits. When you close the tab, that connection's process dies and the Registry removes its entry on its own, because the runtime ties state to process lifetime. No heartbeats, no reaping, no stale-connection bugs. A blocked process per connection sounds expensive until you remember these are BEAM processes, a few kilobytes each.

A broken edit prints its diagnostics and the last good output keeps serving, which falls out of the architecture rather than being engineered: the build is a pure function over the tree, and a failed build never touches `_site/`.

My favourite part has no algorithmic content at all. A file watcher that *starts* is not a file watcher that *works*: on a Docker bind mount, inotify will accept the subscription and never deliver an event. So the watcher writes a probe file where your edits actually happen and waits for the event to come back. If it doesn't, the watcher says so, out loud, and returns `:ignore`, the standard "leave me out of the tree" child-start value. The server keeps serving without live reload, the `--json` envelope carries `live_reload: false`, and nothing has lied to anyone.

Read the whole thing, including the ephemeral-port trick that keeps CI runs from fighting over port 4000: [The embedded server, on cherrybomb.dev](https://cherrybomb.dev/the-embedded-server/).
