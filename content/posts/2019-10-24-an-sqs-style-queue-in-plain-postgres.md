---
title: "An SQS-style queue in one Postgres table"
description: "Two of our products needed to pass messages, and the service between them already ran on Postgres. One table, FOR UPDATE SKIP LOCKED and a timestamp watermark give you pull delivery, visibility timeouts and at-least-once semantics with no broker to operate. The mechanics, the indexes it needed, and the line past which you buy SQS after all."
tags: [work, elixir, postgres, sql, distributed-systems]
draft: true
---

The 2019 catalogue for "we need a message queue" is well stocked: RabbitMQ if you enjoy operating brokers, Kafka if you enjoy operating Kafka, SQS if you'd rather pay Amazon a fraction of a penny per million messages. At work I picked none of them. The integration service I've been building to carry messages between two of our products already stands on Postgres, and an SQS-shaped queue fits in one table with the right locking clause on the read. The queue arrived with backups, monitoring and a pager rota it did nothing to earn, because the database was already there.

I've written about this service's contract in [linking accounts across apps that don't share a login](/one-protocol-four-front-doors/): delivery is pull-based and at-least-once, ordering is refused on purpose, idempotency is the consumer's job. That post is the promises. This one is the machine that keeps them.

## The case for the boring queue

The argument was operational before it was technical. It's a small service, and a broker would double what it takes to run it: a cluster to patch, a second failure domain in every incident, one more diagram in the onboarding doc. Postgres was already holding the domain records, so adding a table to a database you operate anyway is close to free.

The technical argument is the one I'd defend in a design review, though. When the queue lives in the same database as your state, one transaction can cover both, so receiving a batch and marking it claimed is a single atomic step. The queue and the database can never disagree about a message, which means there's no reconciliation code, which is the code that's always wrong.

The bet isn't eccentric this year either. Oban appeared in the spring, putting background jobs in Postgres for a single application; this makes the same wager one level up, between applications, at traffic (tens of messages a second at worst) Postgres barely notices.

## One table, three statuses

Each message is a row: a topic, a type and a JSON body (the protocol's envelope), a `visibility_timeout_ms` the sender picks (validated into the range one second to twelve hours, thirty seconds by default), a `visible_at` timestamp we'll get to, and a `status` backed by a real Postgres enum: `visible`, `invisible`, `acknowledged`. Rows are scoped to the pair of linked accounts they belong to, and the sender's id is on the row so the receive query can exclude your own sends: within a channel, you pull what the other side wrote.

A message's life is a short walk along that enum. Born `visible`. Received, so `invisible`. Acknowledged, and it never comes back: acknowledged rows stay in the table, because they're the audit trail, and archiving them is a batch job's problem rather than the queue's.

## A receive claims rows

A receive is one transaction, two statements. The first selects and locks the next batch of eligible rows; the second stamps the claim onto them; committing releases the locks.

```elixir
# the queue module
Repo.transaction(fn ->
  # Select Messages with "LOCK FOR UPDATE"
  query =
    QueryBuilder.read_and_lock(channel_id, application_id, count, topic, type)

  messages = Repo.all(query)

  # Set the read messages as "invisible"
  messages
  |> Enum.map(& &1.message_id)
  |> QueryBuilder.set_invisible_by_id()
  |> Repo.update_all([])

  # Return messages and unlock rows when transaction ends
  messages
end)
```

The select is where the queue lives. Eligible means `status = 'visible'`, or `invisible` with a `visible_at` already in the past (that's redelivery, coming shortly). It orders by insertion time, takes at most `count` rows (ten by default), and ends with the load-bearing clause: `FOR UPDATE SKIP LOCKED`.

`FOR UPDATE` turns the select into a claim: rows come back locked and stay locked until commit. `SKIP LOCKED` is what turns row locking into a queue. Without it, a second consumer running the same query stops dead at the first consumer's locks and waits, so your parallel consumers secretly take turns. With it, the second consumer hops over anything claimed and takes the next ten. Two consumers polling the same channel never see the same message and never wait for each other. Postgres has had the clause since 9.5 in early 2016, and the release notes name queue-like tables as the reason it exists.

## A visibility timeout with no timers in it

The claim stamp is the second statement, and it's the entire visibility-timeout implementation:

```elixir
# the queue module (QueryBuilder)
def set_invisible_by_id(ids) do
  Message
  |> where([m], m.id in ^ids)
  |> update([m],
    set: [
      status: ^:invisible,
      visible_at:
        fragment(
          "((clock_timestamp() at time zone 'utc') + (? * interval '1 millisecond'))",
          m.visibility_timeout_ms
        )
    ]
  )
end
```

Every received row goes `invisible` and gets a `visible_at` watermark: now plus its own sender-chosen timeout. That's the whole redelivery machine. Nothing wakes up to requeue expired messages. Re-eligibility is a predicate, evaluated by the next receive: an `invisible` row whose watermark has passed matches the select again, and back it comes. A consumer that crashes mid-batch does nothing at all to recover its messages; time does it. This is my favourite property of the design, because the usual broker answer to "what redelivers the message" is a component, and here the answer is a WHERE clause.

One line of small print: it's `clock_timestamp()`, and the more familiar `now()` would be subtly wrong. `now()` freezes at the start of the transaction, so a batch claimed late in a long transaction would carry watermarks computed from its beginning, quietly shortening the consumer's grace period. `clock_timestamp()` reads the wall clock at execution.

## Acknowledgement is an update that counts rows

SQS calls the last step delete; here it's acknowledge, and it's a conditional update:

```elixir
# the queue module (QueryBuilder)
def acknowledge_message(message_id, channel_id, _application_id) do
  # ...
  Message
  |> where([m], m.id == ^message_id)
  |> where([m], m.channel_id == ^channel_id)
  |> update([m], set: [status: ^:acknowledged])
end
```

The channel scope rides along with the id, so a caller can only acknowledge messages their token proves are theirs. The affected-row count is the result: one means done; zero means go and diagnose, and only then does the code spend a second query separating "no such message" from "not your message". The happy path costs one UPDATE. Concurrency got its own test: one process holds a receive's row locks open in a transaction while another acknowledges the same message, pinning down that the ack lands cleanly once the claim releases rather than erroring or deadlocking.

## Two indexes, both earned

The first cut shipped with no indexes beyond the primary key. Two followed within the week: a composite matching the receive predicate (channel scope, status, watermark, topic, type) and one on `inserted_at`, because the ORDER BY was otherwise sorting everything eligible on every poll. Neither is clever, and that's rather the point: a queue on a database makes you own the query plans. SQS never shows you one; this table shows you nothing else.

## Where the table stops

I'll buy SQS without a fight when any of these lines gets crossed, and knowing the lines is part of choosing the pattern.

Throughput: every receive is a write and every redelivery is another, so a hot queue is a steady drip of dead tuples for autovacuum, and the table wants vacuum tuning long before Postgres runs out of raw speed. Poison messages: this schema has no receive counter, so a message that reliably crashes its consumer comes back every timeout, forever; SQS's dead-letter redrive is exactly the feature you discover you were missing at 3 a.m. Latency: consumers here poll on an interval, so you trade freshness against load, where SQS will hold a long poll open for twenty seconds. And coupling: queue traffic and domain queries share one database's capacity, so a message storm is also a database incident.

The service's traffic sits nowhere near any of those lines. But the semantics were copied from SQS deliberately, so that crossing one someday makes the migration a storage swap behind an API that already speaks visibility timeouts and acknowledgement. Consumers wouldn't notice.

## If you're tempted

If you already run Postgres and your volume is measured in tens per second, you already own a message queue: a table, `FOR UPDATE SKIP LOCKED` and a watermark column are the whole machine, and the transactional boundary you gain is worth more than most broker features. Model timeouts as data instead of timers; a re-eligibility predicate needs no scheduler and survives crashes by doing nothing. And when you hand-roll a managed service's semantics, copy them faithfully, so that buying the real thing later is a migration rather than a redesign. Go and play with `SKIP LOCKED`; it's the best queue primitive most folks have never used.
