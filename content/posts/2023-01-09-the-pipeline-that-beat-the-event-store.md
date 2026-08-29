---
title: "When a flag column beats an event store"
description: "Ingesting a partner's changes from a shared database: a prioritised, idempotent, ack/nack pipeline on Broadway, and the Commanded event-sourcing spike I ran first to make sure boring was the right call."
tags: [work, elixir, otp, postgres, distributed-systems, design-docs]
draft: true
---

Some integrations hand you an API. This one hands you a database. The partner we integrate with at work publishes changes by inserting rows into a schema both sides can reach: a table per entity type, every row a changeset with a monotonically increasing id and a status column. Your half of the contract is to read the new rows, apply them to your own model, and flip the status. There is no API in front of it. The protocol is a column.

I lead the ingestion side of that feed. And because it was 2022 and the rows even *look* like events, my first move was a Commanded spike, to see whether the whole thing wanted to be event sourced. It didn't. The reasons why turned out to be more useful than the pipeline itself, so here are both.

## the ack channel is a column

Squint at a status column whose values mean unprocessed, processed, errored and rejected, and it's a messaging protocol. Ack is an `UPDATE` that marks the row processed. Nack marks it errored, for something worth retrying, or rejected, for a row too malformed to try again. The delivery guarantee is at-least-once, because the durable cursor is the status itself: the client keeps an in-memory high-water mark per type so it doesn't rescan on every poll, but that state is disposable. Crash, restart, and it re-sweeps anything still unprocessed. It reads errored rows back in too, which gets you retry-on-error without building a retry system.

```elixir
# illustrative: the shape of one poll for one entity type
from cs in schema,
  where: cs.changeset_id > ^last_seen,
  where: cs.status in [:unprocessed, :errored],
  order_by: [asc: :changeset_id],
  limit: ^demand
```

At-least-once means consumers will see rows twice, so applying a changeset has to be idempotent: an upsert keyed on the entity, with the changeset id along for the ride as the idempotency key. Once that holds, redelivery is harmless and the failure story collapses to one rule. If you can't apply a row, nack it, because an unflagged failure will be retried until the heat death of the universe.

## parents before children

The entity types reference each other. Drain the tables in the wrong order and you'll apply a child row whose parent hasn't arrived yet, and you've manufactured a missing-reference failure the partner never sent you.

So the client walks the types in a configured priority order, and that order is simply the topological order of the foreign keys. Each fetch visits the types in sequence, each with its own cursor, topping up one bucket until it holds a full batch. If a full lap over every type yields less than a batch, it takes one more lap and returns what it has. Nothing clever, and the clever part sits upstream of it: get the ordering right once, in configuration, and a whole class of failure mostly stops existing.

## poll for demand, ack in batches

Over the client sits a Broadway pipeline fed by a GenStage producer. If you haven't met them: GenStage is Elixir's abstraction for a pipeline of stages in which consumers *ask* producers for work, so a slow consumer is never buried (that's back-pressure, built into the protocol between stages rather than bolted on). Broadway is the batteries-included pipeline on top of it, with producers, processors, batchers and acknowledgement, and concurrency as configuration. The producer here remembers demand it couldn't fill, polls again every few seconds, and picks up whatever the partner has inserted since.

A transformer wraps each changeset in a message whose acknowledger is a batching one, and this is the bit worth stealing:

```elixir
def transform(event, _options) do
  %Broadway.Message{
    data: event,
    acknowledger: {Pipeline.Acker, :ack_batch, []}
  }
end
```

Acking one row at a time is a network round trip per row into a database you don't own. The batch acker groups a completed batch by entity type and issues one `UPDATE ... WHERE changeset_id IN (...)` per type, inside a single transaction, so 64 acknowledgements cost a handful of statements. Processing is single-file, because order matters; acknowledgement fans out across every core, because it doesn't. In most stacks that split is a design with a queue library and a thread pool behind it. Here it's two numbers in the Broadway config.

## the spike that made boring defensible

Before any of that existed I spent a week or so with Commanded and EventStore in a throwaway repo, building the smallest real version of the event-sourced alternative: aggregate, command, event, router, an in-memory event store for tests. The aggregate, condensed:

```elixir
def execute(%School{school_code: nil}, %CreateSchool{} = cmd) do
  %SchoolCreated{school_code: cmd.school_code, name: cmd.name}
end

def execute(_school, %CreateSchool{}), do: {:error, :school_exists}

def apply(%School{} = school, %SchoolCreated{} = event) do
  %School{school | school_code: event.school_code, name: event.name}
end
```

Commanded is lovely, and the spike worked. The pitch for it here was real, too: our roadmap talks about spinning read stores up and down from an event log, and a full audit trail of everything the partner ever told us sounds like something you'd want.

What the spike made obvious is that everything arriving on this feed is already a fact. A changeset is a decision someone else has already made, so there is no command for us to validate and no invariant for an aggregate to protect. An aggregate wrapped around an inbound row has exactly one behaviour: copying fields into state. An event store fed that way is a second event log sitting downstream of the real one, because the partner's tables already are an ordered, replayable log with a cursor. Want to rebuild from history? Point a fresh client at changeset zero and let it sweep.

So the trade was a second event-store schema to operate, serialisers, projections and process managers across a couple of dozen types, all to mirror facts we can re-read at will from the system of record. On a build team of two, that's a lot of ceremony for a copy machine. Event sourcing earns its keep where you own the decisions. Here we own none of them, and the plain pipeline gives us the properties we actually wanted (ordering, replay, at-least-once with idempotent apply) from one Postgres connection and a status column.

## where it stands

The pipeline now drains every entity type in priority order against a pre-production copy of the feed, with errored rows swept back in on later passes. The unglamorous tail remains: failures are currently counted and logged, and wiring them through to a proper nack is next on the list.

## what travels

Treat a shared-database integration as a messaging protocol and write it down as one, with delivery guarantees, ack semantics and retry rules, before writing code; the moment we started saying ack/nack, every design conversation got shorter. Derive ingestion priority from the foreign keys, since dependency order is a property of the data model and belongs in configuration. And spike the exciting option first, in a repo you intend to throw away. The spike is what lets you pick the boring design on evidence rather than temperament, and the question it taught me to ask is: who owns the writes? If the events already exist somewhere else, you can have most of event sourcing's benefits without an event store. Somewhere I do own the writes, Commanded stays on my list.
