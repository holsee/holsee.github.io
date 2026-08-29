---
title: "Chroxy: raw DevTools connections from a headless Chrome pool"
description: "Open-sourcing the Elixir proxy I wrote to hand out thousands of raw DevTools connections from a headless Chrome pool. A transparent TCP proxy, one process per connection, and a race I got wrong the first time."
tags: [personal, elixir, otp, headless-chrome, oss]
draft: true
---

I've just pushed [Chroxy](https://github.com/holsee/chroxy) up under an MIT licence. It's an Elixir service that sits in front of a pool of headless Chrome processes and hands out Chrome DevTools connections on demand, and it was, honestly, born out of necessity: I needed to orchestrate a large number of concurrent browser scenarios with low-level control, and the tools to hand were the wrong shape.

## Why not Hound or Wallaby

Those are browser-*testing* frameworks. They wrap the browser in a nice testing API, which is exactly what you want for a test suite and exactly what's in your way when you want the protocol itself. From the project goals:

> Unlike browser testing frameworks such as `Hound` and `Wallaby`, Chroxy aims to provide direct unfettered access to the underlying browser using the Chrome Debug protocol whilst enabling many 1000s of concurrent connections channelling these to an underlying chrome browser resource pool.

So: raw CDP, pooling and lifecycle handled elsewhere, thousands of connections. That's the brief.

## The whole public API is one endpoint

You ask for a connection and you get a WebSocket URL. That's it:

```elixir
# lib/chroxy/endpoint.ex
get "/api/v1/connection" do
  endpoint = Chroxy.connection()
  send_resp(conn, 200, endpoint)
end
```

and `Chroxy.connection/0` is a one-liner onto the pool. Speak CDP down the returned `ws://` and Chroxy stays out of the way. The page is created when you connect and closed when your socket closes.

## The trick: the URL points at the proxy, not at Chrome

Chrome advertises its own WebSocket debugger URL for each page. Chroxy rewrites it (string-replaces the port, then the host) so the client only ever talks to the proxy:

```elixir
# lib/chroxy/chrome_proxy.ex
defp proxy_websocket_addr(%{"webSocketDebuggerUrl" => websocket}) do
  proxy_opts = Application.get_env(:chroxy, Chroxy.ProxyListener)
  proxy_host = Keyword.get(proxy_opts, :host)
  proxy_port = Keyword.get(proxy_opts, :port)
  uri = URI.parse(websocket)

  websocket
  |> String.replace(Integer.to_string(uri.port), proxy_port)
  |> String.replace(uri.host, proxy_host)
end
```

Yes, that's `String.replace` on a URL, and yes it makes me twitch a little too. It works because the host and port are distinctive enough in a devtools URL. Once the client is pointed at the proxy, Chroxy owns both ends of the connection, and everything else is possible.

## One process per connection, monitors on both ends

`ProxyListener` holds a single `gen_tcp` listener (Erlang's TCP socket API, in the standard library). When a connection is accepted it spawns a dedicated `ProxyServer`, a GenServer (a process with state and a mailbox), and hands it the socket. Processes on the BEAM cost a few kilobytes each, so one per connection is the obvious design rather than an extravagance:

```elixir
# lib/chroxy/proxy_listener.ex
{:ok, proxy} =
  Chroxy.ProxyServer.start_link(
    upstream_socket: upstream_socket,
    proxy_opts: proxy_opts
  )

# set the spawned proxy as the controlling process for the socket
:gen_tcp.controlling_process(upstream_socket, proxy)
```

`ProxyServer` is then a symmetric relay: two `handle_info` clauses, one per direction, told apart purely by pattern-matching which socket the `{:tcp, socket, data}` arrived on against the sockets pinned in its state. The bit that matters is the teardown. Either socket closing tears the whole thing down and fires the `down` hook:

```elixir
# lib/chroxy/proxy_server.ex
def handle_info({:tcp_closed, downstream_socket}, state) do
  Logger.warn("Downstream socket closed, terminating proxy")
  # ... fire the down hook ...
  :gen_tcp.close(downstream_socket)
  :gen_tcp.close(upstream_socket)
  {:stop, :normal, state}
end
```

No reaper process, no timeout sweep looking for orphaned pages. The process owns exactly one connection's worth of resources, and when either end goes, the process goes, and its Chrome page goes with it. In most runtimes a proxy like this keeps a connection table and a janitor thread; here the connection *is* the process, so the table and the janitor don't exist. Leaked pages are what slowly kill a long-running headless Chrome box, and this shape makes them hard to create.

## A behaviour as the seam between proxy and browser

I wanted the proxy to know nothing about Chrome. So the browser-specific logic lives behind a behaviour (Elixir's interface: a set of callbacks a module promises to implement) with two callbacks:

```elixir
# lib/chroxy/proxy_server.ex
defmodule Hook do
  @callback up(identifier(), Keyword.t()) :: [
              downstream_host: charlist(),
              downstream_port: non_neg_integer()
            ]
  @callback down(identifier(), Map.t()) :: :ok
  @optional_callbacks up: 2, down: 2
end
```

`ChromeProxy` implements it: `up` returns where to connect downstream, `down` closes the Chrome page. The proxy underneath is a generic TCP relay that could front anything. It's a small pattern and I reach for it constantly: a behaviour as the seam between *how bytes move* and *what the bytes mean*.

## The race I got wrong

Here's the part worth the write-up. The first cut resolved the downstream target eagerly, when the proxy started. That's fine until two clients ask for connections and then connect in the *opposite* order, because the proxy that accepts the first inbound socket isn't necessarily the one whose page that client asked for. I had a race, and issue #5 was it.

The fix is to defer. The proxy waits for the client's first TCP packet, reads the Chrome page id straight out of the HTTP upgrade line, looks up the owning process in an ETS table, connects downstream *then*, and re-sends the packet to itself so the normal relay clause handles it:

```elixir
# lib/chroxy/proxy_server.ex (first-packet clause)
hook = dyn_hook && dyn_hook.(data)
hook_opts =
  if hook && function_exported?(hook.mod, :up, 2) do
    apply(hook.mod, :up, [hook.ref, state])
  end
# ... connect downstream using hook_opts ...
{:ok, down_socket} = :gen_tcp.connect(downstream_host, downstream_port, downstream.tcp_opts)

# Reschedule this TCP message now that downstream connection is available
send(self(), msg)
```

The page-id parser is unglamorous string surgery on the request line (`String.split(" HTTP")` then `String.split("GET /devtools/page/")`), and the lookup table is a named ETS set (ETS is the runtime's built-in in-memory table) whose owner `Process.monitor`s each proxy, so the runtime tells it when one dies and the entry is cleaned out. The regression test for it is my favourite kind: it just does the wrong-order thing and asserts the process didn't crash:

```elixir
# test/chroxy_test.exs
# Connect to 2nd connection first
_page_1 = ChromeRemoteInterface.PageSession.start_link(conn_1)
_page_0 = ChromeRemoteInterface.PageSession.start_link(conn_0)

# Should not have crashed
assert true
```

"Should not have crashed" is doing a lot of quiet work in that test, and it's the honest assertion for a concurrency fix.

## Chrome is an OS process, so supervise it like one

`ChromeServer` wraps each browser with `erlexec` (through `exexec`) so it sits in the supervision tree, the same restart-on-crash machinery that guards Elixir processes, and a browser that dies is treated like any other failed child and started again. It also reads Chrome's log output and turns it into `Logger` levels and, more usefully, into state. Readiness is literally inferred from a log line:

```elixir
# lib/chroxy/chrome_server.ex
def handle_info({:stdout, pid, <<"\r\nDevTools listening on ", _rest::binary>> = msg}, state) do
  chrome_port = Keyword.get(state.options, :chrome_port)
  session = Session.new(port: chrome_port)
  {:noreply, %{state | session: session}}
end
```

and a couple of Chrome's log lines are treated as fatal: a `bind()` failure on the debug port terminates the server rather than leaving a wedged browser:

```elixir
def handle_info({source, pid,
    <<_::size(@log_head_size), ":ERROR:socket_posix.cc(143)] bind()", _::binary>>}, state)
    when source in [:stdout, :stderr] do
  Logger.error("[CHROME: #{inspect(pid)}] Address / Port already in use. terminating")
  Exexec.stop_and_wait(pid)
  {:stop, :normal, state}
end
```

I'll be honest that scraping Chrome's stderr for `"DevTools listening on "` and matching a fixed 19-character log-header width is brittle: a Chrome release that reworded either would break readiness detection silently. There's a `TODO` in the file admitting the log parsing wants its own module. It hasn't bitten yet.

Above it, `BrowserPool` spawns one Chrome per port across a configured range and hands them out round-robin, deriving the live pool from the supervisor's children and filtering to the ready ones. All configuration is env vars (`CHROXY_CHROME_PORT_FROM`/`_TO`, the proxy host and port), because this was always going to run in containers, and the README ships a Dockerfile, the `--shm-size 2G` warning you otherwise learn painfully, and a Kubernetes sidecar example.

## What it was for

Chroxy was born inside a performance harness at work, for a document-viewer product. A viewer is a bad thing to time with `curl`: the number a user feels isn't when the HTTP response arrives, it's when the document is on the screen and readable. So the harness drives a real browser through the product and times the journey in stages (the embed page loads, the document is reported processed, the content is actually painted), waiting on the exact elements in the viewer's own DOM that change when the user's screen does:

```elixir
browser = Browser.open!
try do
  with {:ok, r} <- measure(%{}, :time_browser_embed_page_load, "GET embed page",
                           fn -> Browser.goto(browser, url) end),
       {:ok, r} <- measure(r, :time_browser_doc_ready, "document processed",
                           fn -> Browser.assert_has(browser, doc_processed_sel) end),
       {:ok, r} <- measure(r, :time_browser_doc_rendered, "content rendered",
                           fn -> Browser.assert_has(browser, content_loaded_sel) end),
    do: {:ok, r}
after
  Browser.close!(browser)
end
```

`Browser.open!` is one line onto chroxy: acquire a page session against the local endpoint and drive it over the DevTools protocol. It was Wallaby before, and PhantomJS before that, and the swap to chroxy is the moment the harness stopped fighting its browser layer. A testing framework wants to wrap the browser in assertions and sessions; a load test wants raw connections, lots of them, with pooling somewhere I control. The harness runs from several AWS regions at once, so the latency in its numbers is real distance rather than a simulated delay, and "slow far away" is a line on a chart. The tooling was in the way, so it became a project of its own.

## What's here

About 840 lines of Elixir across eight modules, twenty-eight dependencies resolved, one integration test that drives a real Chrome and asserts it gets a `ws://` back. It's version 0.2.0 and its infancy shows in a couple of places: there's a `# HACK to get exec running as root` at the top of the application, and a stray `Logger.warn("ARGS: []")` on every boot that I should delete. But the bones are right: a transparent proxy, a process per connection with monitors on both ends, a behaviour between the proxy and the browser, and Chrome under a supervisor.

If you're driving headless Chrome from the BEAM and the testing libraries are in your way, [give it a go](https://github.com/holsee/chroxy) and tell me what breaks. That's what the issue tracker is for.

## Where to look

- Repo: https://github.com/holsee/chroxy (MIT); hex package `chroxy`.
