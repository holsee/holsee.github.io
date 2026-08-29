---
title: "A realtime relay on Phoenix PubSub"
description: "A message relay for browsers on Phoenix Channels and PubSub: one JWT claim names the scope, one string equality is the whole authorisation layer, and fan-out across a cluster comes free. Plus the database I deleted on day two."
tags: [work, elixir, phoenix, realtime, api-design]
draft: true
---

I needed a realtime layer the rest of the platform could lean on: something a product could point a browser at, authenticate against, and start receiving messages from, without every product reinventing WebSockets. What I built at work is a message relay over Phoenix Channels, and the thing I like about it is how little of it there is. The whole security model is a single string comparison, and a "scope" is one pub/sub topic. This is a post about a design small enough to keep entirely in your head, and about how much of it the BEAM does for you.

## two words, before the code

If you haven't met Phoenix, two pieces of vocabulary carry this whole post. A Channel is Phoenix's abstraction over a WebSocket: the browser joins a named topic, and on the server that join becomes a lightweight process (a few kilobytes of memory, one per connected client) which can receive messages and push events down the socket. PubSub is the runtime's built-in publish and subscribe: any process can broadcast a message on a topic, and every process subscribed to that topic gets it, on this node or any other node in the cluster. Between them they replace a socket server, a message broker, and the bookkeeping that maps one onto the other. That isn't an exaggeration, and the rest of this post is meant to show why.

## a scope is one topic

The core idea: messages are relayed within a *scope*, a scope is named by a `session_id`, and that `session_id` is a claim inside the signed JWT the browser connects with. That one value does four jobs at once. It's the JWT claim. It's the channel topic you join (`"relay:" <> session_id`). It's the pub/sub topic a message is broadcast on. And it's the socket's disconnect id, so revoking a session drops every socket on it. Four responsibilities, one string.

Which means membership of a scope is provable, not stored. You're in the scope if you hold a JWT whose `session_id` matches the channel you're joining, and the check for that is the entire authorisation layer:

```elixir
def can_join_channel?(token, session_id) do
  session_id == token.session_id
end
```

That's it. No roles, no per-topic ACLs, no membership table. A signed token proving which scope you belong to, and one equality. I'll defend the smallness: this is infrastructure, and infrastructure you can't fully reason about is infrastructure that will surprise you at 2am. Anything richer (who may publish what, when a session should end) belongs to the product on top, which knows its own rules. The relay's only job is "same scope, or nothing", and it does exactly that.

## two doors onto the same fan-out

There are two ways to publish, and they converge on the same broadcast. A connected client pushes over its channel:

```elixir
def handle_in("publish", %{"topic" => topic, "message" => message}, socket) do
  broadcast!(socket, topic, message)
  {:reply, {:ok, message}, socket}
end
```

`handle_in` is the callback Phoenix runs when a client sends an event on the channel, and `broadcast!` delivers it to every process subscribed to this channel's topic, which is every browser in the scope. Or a server with no socket of its own sends an HTTP request carrying a JWT, and the relay broadcasts straight onto that token's scope:

```elixir
def publish(jwt, topic, message) do
  case Auth.authorise_connection(jwt) do
    {:ok, token} ->
      Phoenix.PubSub.broadcast(PubSub, "relay:" <> token.session_id,
        %{topic: topic, message: message})

    {:error, :unauthorised} = err ->
      err
  end
end
```

The neat part is what the *app* topic becomes. The channel topic is the scope; the app's own `topic` rides along as the Phoenix event name, so a client filters with `channel.on(topic, ...)`. Scope is the security boundary, enforced by the channel; topic is a soft routing label the client sorts by.

And here is the part that costs a whole project elsewhere. The pub/sub adapter is PG2, which uses the BEAM's built-in process groups to fan a broadcast out to every node in a cluster, so the same three lines work on one box or ten. There's no Redis in the middle, no sticky sessions, no table of which server each browser is connected to. A browser attached to node A gets a message published on node C because the runtime already knows where every subscriber lives.

## the database I deleted

Here's the bit of history I'm fond of. The relay began as an ordinary Phoenix app: generated with a database, Ecto, Postgres, the lot. On the second day I took the database out. A relay has nothing to persist. Messages pass through it; they don't live in it. The scaffold gave me a database out of habit, and the honest move was to notice I had no rows to put in it and remove it.

What was left is a stateless relay whose entire state is "which sockets are on which topic", and the runtime already tracks that, in the channel processes themselves. When a browser goes away its channel process dies and the subscription dies with it. Nobody writes a reaper, nobody stores a last-seen timestamp. Deleting the database wasn't a cut corner; it was the design becoming what it actually was.

## the design I meant to ship, still in the tree

One confession, because it's the most useful kind of detail. There's a module in there that describes a composite topic (`session_id:app_topic`) with a `create` and a `split`. It is never called. Nothing in the shipped relay uses it. It's the design I sketched first (encode both dimensions into one topic string) and then didn't build, because scoping by the channel topic and carrying the app topic as the event name turned out simpler and did the job. I left the module in rather than pretend I'd gone straight to the answer. If you read the code, you can see the road not taken sitting right next to the road taken, which is the truest map of how anything gets built.

## what I'd keep

Make the smallest thing that could possibly relay a message safely, and resist every urge to make it clever. One value that names the scope, one equality that guards it, one broadcast that delivers. Delete the database you don't need. And let the runtime hold the connection state, because it already does.

It shipped containerised behind TLS and cluster-ready, with a JavaScript client alongside it: a relay, not a fortress, and deliberately so. The whole thing is a channel module, an auth module and one controller. In most ecosystems the equivalent is a socket server, a broker and the glue between them, plus the on-call rota that comes with three moving parts.
