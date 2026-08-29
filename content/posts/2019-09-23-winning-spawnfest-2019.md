---
title: "exile: a realtime database that grows its own schema"
description: "A realtime NoSQL store where the URL is the schema, collections spring into existence when you write to them, and a browser gets live updates for the price of one subscribe call. Built in 48 hours on ETS, processes and Phoenix Channels, and it won."
tags: [community, elixir, otp, ets, phoenix, liveview, realtime]
draft: true
---

We won Spawnfest this weekend. Trading as The Bodgemasters, we built exile over Saturday and Sunday, and it took the top spot. The idea was one I'd been wanting to try for a while: a database you talk to like a REST API, where the paths *are* the schema, where a collection exists because somebody wrote to it, and where any browser can subscribe to a path and be told the moment it changes. An API and a database with zero backend code. It's Monday, the adrenaline's gone, and I want to write down how it works while I still remember, because the bet underneath it is the reason it could be built in a weekend at all.

## the pitch

Spawnfest is the BEAM community's 48-hour hackathon: a weekend, a fresh repo, judges from the Erlang and Elixir world. The demo we showed was a blog written entirely in browser JavaScript. No server-side code, no migrations, no models:

```js
exile.post('posts', {author: 'holsee', title: 'Hello World', comments: []})
//=> {result: 'ok', reference: 'posts', value: '04c7fecd-9e3f-...'}

exile.post(`posts/${post_id}/comments`, {author: 'evadne', body: 'nice!'})
exile.get(`posts/${post_id}/comments`)
exile.subscribe('posts')   // every change under posts/ now arrives as an event
```

Open the same page in a second tab, post a comment in one, watch it appear in the other. Nobody wrote a `posts` table, a `comments` table, a route, a controller or a WebSocket handler. The paths in those calls are the only schema there is.

The bet was that the BEAM already contains the product. Elixir runs on the Erlang virtual machine, and the VM ships with an in-memory key-value store (ETS), millions of cheap isolated processes that can find each other by name, and a runtime that tells you when a process dies. Phoenix, the web framework, adds Channels for the WebSocket. So the product layer can be thin, and thin is what you can build in a weekend. I took the store engine, the `exile` application underneath the web app, and that's what this post is about.

## the URL is the schema

There is no schema in exile. A path like `posts/8b1e.../comments/c4d2...` is parsed segment by segment, and the only question asked of each segment is: does it cast as a UUID?

```elixir
# apps/exile/lib/exile/path.ex (condensed)
def parse(path) do
  path
  |> String.split(@delim)
  |> Enum.filter(&(&1 != ""))
  |> Enum.map(fn value ->
    if Exile.Id.is_id?(value), do: {:id, value}, else: {:type, value}
  end)
end
```

A segment that parses as a UUID is a record id; anything else is a collection. `posts` becomes `[type: "posts"]`, and `posts/<id>/comments` becomes `[type: "posts", id: "...", type: "comments"]`. That's the entire routing model, and it's enough for collections, records, nested collections, nested records, and reading a single attribute (`posts/<id>/author`) out of a record. Every operation in the store starts by pattern-matching on the shape of that list.

## collections exist because you wrote to them

This is the part I find most satisfying, and it's the heart of "the database adapts to the requests". Where does the `posts` collection come from? From the first request that mentions it.

Each collection is one process holding one ETS table. In Elixir a GenServer is a process with state and a mailbox: you send it a message, it handles the message in a callback, it replies. ETS is the VM's built-in in-memory table, so the data lives inside the runtime with no separate database server to run. The store looks up the process for a path, and if there isn't one yet, it asks a supervisor to start it:

```elixir
# apps/exile/lib/exile/store/ets/table.ex
def table_ref(path) do
  table_ref = Exile.Path.to_ref(path)

  case TableSupervisor.start_child(child_spec(table_ref)) do
    {:error, {:already_started, _}} -> via_registry(table_ref)
    {:ok, _} -> via_registry(table_ref)
    error -> raise "Failed to start #{__MODULE__} process: #{inspect(error)}"
  end
end

def post(path, record) do
  GenServer.call(table_ref(path), {:post, path, record})
end
```

Read that `case` slowly, because it's doing what a `CREATE TABLE`, a connection pool and a cache would do elsewhere. `TableSupervisor` is a `DynamicSupervisor`: a process whose job is to start children on demand and restart them if they crash. Ask it to start the `posts` table process and one of two things happens. Either it starts, and its `init` creates a fresh ETS table, or it was already running and the supervisor says so. Both branches return the same thing: a name you can send messages to. The name is resolved through a `Registry`, the runtime's process phone book, so nobody holds a raw process id and a restarted process picks up the same name.

The consequence is that the store has no notion of "creating a collection". The first `POST` to `posts` starts a process. The first `POST` to `invoices` starts another. `DELETE posts` stops the process and its table goes with it. The schema is whatever paths have been written to, and the supervision tree is a live picture of the data model.

## digging into a record by path

Reading `posts/<id>/comments/<id>/author` means walking into a stored value. Records are plain maps and lists (whatever JSON the client sent), and the walk is a recursive pattern match over the parsed path:

```elixir
# apps/exile/lib/exile/store/ets/table.ex (condensed)
def do_access_value(value, []), do: {:ok, value}

def do_access_value(value, [{:type, key} | rest]) when is_map(value) do
  value |> Map.get(key, :not_found) |> do_access_value(rest)
end

def do_access_value([%{id: _} | _] = list, [{:id, id} | rest]) do
  case Enum.filter(list, &(&1.id == id)) do
    [item] -> do_access_value(item.value, rest)
    _ -> :not_found
  end
end
```

A `{:type, key}` segment against a map is a key lookup; an `{:id, id}` segment against a list of records is a search by id; an empty path means you've arrived. Each clause is chosen by the shape of the data and the shape of the path together, which is what pattern matching is for. Posting a nested record (`POST posts/<id>/comments`) is the same walk with an insert at the end: find the root record, find the list, prepend a new row with its own id and timestamp, write the root back.

## realtime for the price of one line

Now the part the demo is built on. Each collection process keeps a list of subscribers alongside its table. When a record changes, it fans out to anyone whose subscribed path is a prefix of the changed path:

```elixir
def notify_subscribers(subscribers, path, event_type, record) do
  subscribers
  |> Enum.filter(&String.starts_with?(path, &1.path))
  |> Enum.map(& &1.address)
  |> Enum.each(&send(&1, {:exile_event, {event_type, path, record}}))
end
```

`send/2` puts a message in another process's mailbox. That's the whole delivery mechanism. Subscribe to `posts` and you hear about `posts/<id>/comments` too, because prefix.

The line I'd point at is the one in `subscribe`:

```elixir
def handle_call({:subscribe, path, subscriber}, _, state) do
  monitor_ref = Process.monitor(subscriber)
  subscriber = %{path: path, address: subscriber, monitor_ref: monitor_ref}
  {:reply, :ok, %{state | subscribers: [subscriber | state.subscribers]}}
end

# condensed: the real clause finds the index and deletes it
def handle_info({:DOWN, monitor_ref, :process, _pid, _}, state) do
  {:noreply, %{state | subscribers: drop_by_ref(state.subscribers, monitor_ref)}}
end
```

`Process.monitor/1` asks the runtime to send you a `:DOWN` message if that process ever exits, for any reason. The web side subscribes with the channel process itself. So when someone closes their browser tab, the channel process dies, the `:DOWN` arrives, and the subscription removes itself. There is no explicit unsubscribe anywhere in the JavaScript or the channel. The monitor *is* the cleanup. In most stacks this is the part where you write a heartbeat, a last-seen timestamp and a job that sweeps stale subscribers; here it's one call to the runtime, and you get it for free.

## the channel is a bridge, not a layer

The Phoenix side is almost embarrassingly thin. A Channel is Phoenix's abstraction over a WebSocket: the browser joins a topic, and the join becomes a process on the server that can receive messages and push events down the socket. Every verb of the JS client is a `handle_in` clause that calls the store:

```elixir
# apps/exile_web/lib/exile_web/channels/database_channel.ex
def handle_in("subscribe", %{"reference" => reference}, socket) do
  :ok = Exile.subscribe(path(reference, socket), self())
  {:reply, {:ok, %{result: "ok"}}, socket}
end

def handle_info({:exile_event, {event_type, path, {id, timestamp, value}}}, socket) do
  push(socket, "event", %{event_type: event_type, path: path,
    record: %{id: id, timestamp: timestamp, value: value}})
  {:noreply, socket}
end
```

`self()` in `handle_in` is the channel process, so the store's `send` lands in this process's mailbox, `handle_info` picks it up and `push` forwards it to the browser. Store to socket is two functions.

The sandboxing is one more line. Each browser session joins `database:<prefix>` with a signed token, and every path is prefixed with that sandbox before it reaches the store. Share the page URL and you share the database; open a fresh one and you get your own. Multi-tenancy in a `Path.join`.

The Data tab on the demo page, which lists the current posts and updates as they change, was a LiveView. LiveView had shipped its first release four weeks earlier, and rendering a live view of an ETS-backed store over a socket turned out to be exactly what it's for.

## what we didn't build

The tagline promised time travel, and the README is candid that the public API for it doesn't exist: every row carries a nanosecond timestamp and there's a function that will sort revisions newest-first, but we ran out of time before wiring versions through to the API. The other honest note is that `String.to_atom` on collection names and a named ETS table per collection is fine for a demo and a bad idea for production. A weekend project is a bet about what you can fake convincingly and what you have to actually build, and we built the store, the paths and the live subscriptions for real.

## what actually shipped

Saturday lunchtime to Sunday night. I built the database, store engine and subscriptions alike; Evadne Wu built the web front end, the "Bodgematic Terminal" REPL, and handled the deployment. It ran on a free Gigalixir dyno for the judging.

The design is the same set of patterns I reach for with no deadline at all: a behaviour for the store interface so the ETS backend could be swapped, a process per collection under a supervisor, registry lookup, monitored subscribers, Channels as the bridge. What made it a weekend's work rather than a quarter's is that every one of those is a primitive the runtime already provides. ETS is the store. Processes and Registry are the routing. Monitors are the cleanup. Channels are the transport. Write the glue that joins them and you have a realtime database that grows its own schema. That's the thing I'd wanted to try, and the reason I'd wanted to try it on the BEAM.

## Where to look

- Repo: https://github.com/spawnfest/exile (my fork: `holsee/exile`).
