---
title: "MCP on the BEAM: a session is a process"
description: "Implementing the Model Context Protocol in Elixir: sessions as supervised GenServers, SSE streams as process mailboxes, resumption as replay, and the small strange shape of OAuth 2.1 for MCP servers."
tags: [personal, elixir, otp, mcp, agents, oss]
draft: true
---

Somewhere in the middle of implementing the Model Context Protocol I stopped translating. The spec wants a stateful session per client, an initialise handshake, server-push notifications over a long-lived stream, resumption after a dropped connection, and clean teardown. That's four things OTP already has names for. (OTP is the set of behaviours the Erlang runtime ships for building servers out of processes; a GenServer is its generic server process, and "supervised" means a parent process restarts it if it crashes.) A session is a supervised GenServer. Push is `send/2`. Resumption is replaying a buffer you kept. Teardown is a process exiting. So this post is what it takes to speak MCP from Elixir: the protocol's actual shape, how directly it lands on the BEAM, and the places where the spec makes you do real work anyway.

## The shape of the protocol

MCP is JSON-RPC 2.0 with a lifecycle. A client opens with an `initialize` request carrying its `protocolVersion`, capabilities and `clientInfo`; the server answers with its own capabilities and, on the Streamable HTTP transport, an `Mcp-Session-Id` response header the client echoes on every request after. The client confirms with `notifications/initialized`, then it's `tools/list` to discover what you offer and `tools/call` to use it, with the same list/read pairs for resources and prompts. All of that flows client-to-server over POST. The reverse direction, log messages and change notifications the client never asked for, needs its own channel: the client opens a GET with `Accept: text/event-stream` and holds it. DELETE ends the session.

ax_mcp implements the 2025-11-25 revision of that, server and client, inside ax, the agent framework I've been building in Elixir in my own time since mid-January. Agents consume tools from MCP servers and want to be MCP servers, so the protocol layer earned its own library. Defining a server is a handful of macros:

```elixir
# ax_demo/lib/ax_demo/mcp/beam_observatory.ex
tool "process_info", "Get detailed information about a process by PID or registered name" do
  param(:pid, :string, required: true, description: "PID (e.g. 0.123.0) or registered name")

  annotations(read_only: true, idempotent: true)

  handle(fn args, session ->
    case Formatting.parse_pid_or_name(args["pid"]) do
      {:ok, pid} -> {:ok, Processes.info(pid), session}
      {:error, reason} -> {:error, reason, session}
    end
  end)
end
```

`use Ax.MCP` accumulates these into module attributes, and a `__before_compile__` pass emits `__mcp_tools__/0` plus one dispatch clause per tool, so `tools/list` and `tools/call` resolve by function-head matching with nothing to look up at runtime. That snippet is from the demo server, which points MCP at the VM itself: processes, ETS tables, schedulers, supervision ancestry. Asking an LLM to walk a supervision tree over MCP is pleasingly circular.

## A session is a process

Every `initialize` starts a Session GenServer under a DynamicSupervisor (a supervisor whose children are started on demand) and registers it in a per-server Registry (the runtime's process directory) under a fresh id (32 random bytes, base64url, 43 characters) which goes out in the `Mcp-Session-Id` header. The process holds the negotiated version, both sides' capabilities, user assigns, resource subscriptions, and the interesting part: the list of live SSE streams and a bounded buffer of every event it has pushed.

The mapping does real work. Each request resolves its header to a pid with a Registry lookup, and an unknown id is a JSON-RPC error with no session table to sweep. DELETE is one line, `GenServer.stop(session_pid, :normal)`, because the Registry drops dead processes on its own. Session termination and process termination are the same event, which deletes a class of cleanup code I have written in other runtimes and never enjoyed.

## The stream is a mailbox

The part I expected to be fiddly, holding SSE streams open and pushing to them, collapsed into the oldest trick on the BEAM. When the GET arrives, the Plug process upgrades to a chunked response, registers itself with the session, writes an id-only priming event so the client knows the stream is live, and then parks:

```elixir
# ax_mcp/lib/ax/mcp/transport/streamable_http.ex
defp sse_receive_loop(conn, session_pid) do
  receive do
    {:sse_event, event_id, message} ->
      case SSEWriter.write_event(conn, event_id, message) do
        {:ok, conn} -> sse_receive_loop(conn, session_pid)
        {:error, _} -> conn
      end

    :close ->
      conn
  end
end
```

That's the whole streaming machinery. Every BEAM process has a mailbox, and `receive` blocks until something arrives in it, so the process holding the HTTP connection already has an event loop and delivering a notification is `send/2`. The session fans out and buffers as it goes:

```elixir
# ax_mcp/lib/ax/mcp/server/session.ex
def handle_call({:push_notification, message}, _from, session) do
  event_id = SSEWriter.generate_event_id(session.event_counter)

  Enum.each(session.sse_streams, fn {pid, _ref} ->
    send(pid, {:sse_event, event_id, message})
  end)

  # Buffer the event for resumability
  buffer = [{event_id, message} | session.event_buffer]
  # ... trimmed: cap the buffer at session.event_buffer_size (100)

  session = %{session | event_counter: session.event_counter + 1, event_buffer: buffer}
  {:reply, {:ok, event_id}, session}
end
```

The session monitors each registered stream (`Process.monitor/1` asks the runtime for a `:DOWN` message when another process exits), so there's no reaper job to write; a client that vanishes mid-stream is a `:DOWN` message and gets swept from the list.

That buffer is the price of resumption, and it's worth naming the trade. SSE lets events carry ids, and the transport spec lets a server opt in to resumability: a reconnecting client sends the last id it saw in a `Last-Event-ID` header and expects the rest. Ids here are `evt_<counter>`, monotonic per session; on reconnect the transport asks the session for everything after that counter and replays it before entering the loop. The buffer caps at 100 events; a client gone longer than that gets a gap, which I'll take over an unbounded per-session buffer. What reads as a transport feature in the spec is really a state-management obligation. Notice that before promising resumability to anyone.

## The auth is mostly discovery

OAuth 2.1 for MCP turned out smaller and stranger than I braced for. The authorisation spec casts an MCP server as an OAuth resource server only; login, consent, PKCE and client registration all belong to a separate authorisation server that is explicitly not your problem. What is your problem: validate the bearer token on every single request rather than once at session creation, publish RFC 9728 metadata at `/.well-known/oauth-protected-resource` naming the authorisation servers you trust, and answer unauthenticated requests with a `WWW-Authenticate` header carrying a `resource_metadata` URL. The 401 is a teaching response; the client follows it, discovers where to authenticate, and comes back.

In ax_mcp that's a Plug composed ahead of the transport, and validation itself is a behaviour, because your token format is none of the library's business:

```elixir
# ax_mcp/lib/ax/mcp/auth/token_validator.ex
@callback validate(token :: String.t(), required_scopes :: [String.t()]) ::
            {:ok, user_info()} | {:error, validation_error()}
```

One wrinkle is MCP's own. The session id is a capability, and a stolen one would ride someone else's perfectly valid token. So the session binds to a `user_id` at initialise and any later mismatch is a 403. It cost one field on a struct the server already owns.

## The client, inverted

The client half is the same idea pointed the other way: a GenServer per server connection holding transport state, a counter that mints JSON-RPC correlation ids, and a cached tool list. The handshake and `tools/list` run once, and tool calls after that are plain `GenServer.call`s with timeouts. It still offers the older 2025-03-26 protocol revision it was first written against while the server side tracks 2025-11-25; the handshake negotiates a version both ends speak, which looked like ceremony in January and has already justified itself. The revision string moves faster than my library does.

## What carries over

When a protocol wants stateful sessions, server push and teardown, look hard at what your runtime already provides before writing a session manager. Here the whole apparatus was a supervised process per session, a Registry, and monitors; most of the cleanup logic simply refused to exist.

Keep transport lifetime and session lifetime apart. Connections are flighty and sessions aren't, so let the connection be a disposable process that registers with the durable one, and let replay paper over the joins.

And read the auth spec before dreading it. For a server, OAuth 2.1 in MCP is discovery metadata, per-request validation and honest 401s; the interactive machinery lives elsewhere, and the parts that remain are exactly the ones you'd want to own.

## Where to look

- The MCP specification (revision 2025-11-25): https://modelcontextprotocol.io/
- RFC 9728 (protected resource metadata) and RFC 6750 (bearer token usage) are the two RFCs behind the auth section.
