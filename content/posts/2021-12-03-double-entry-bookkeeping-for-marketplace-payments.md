---
title: "Double-entry bookkeeping for a marketplace"
description: "In a marketplace, money moves in several directions at once, and a balance column can't tell you where it went. The pattern that can: a three-table double-entry ledger, and idempotency keys at the Stripe boundary."
tags: [work, elixir, postgres, payments, design-docs]
draft: true
---

Follow one booking through a marketplace and count the directions money moves. A customer pays $100 by card. The platform keeps $15. The coach is owed $85 and gets paid out days later. Then the session is cancelled, the customer is refunded, and the payout has to come back. Four movements, two directions, and at any moment someone in finance can ask the only question that matters: where is the money right now?

If the answer lives in a balance column (`UPDATE accounts SET balance = balance - 85`), you don't know. You know what the column says. Those are different things, and the gap between them is where I've spent a chunk of this year.

The product is a coaching marketplace I've been building at work: educators book and pay for live one-to-one sessions with a coach, and the coach is paid out afterwards. This year has mostly been its payments path: Stripe Checkout for cards in the spring, refunds and Stripe Connect payouts for coaches by early summer, and, merged this week, support for organisations paying from a balance they hold with the platform. That last piece forced the bookkeeping question properly into the open, so this post is the pattern I'd now reach for anywhere money moves in more than one direction: a small double-entry ledger, plus idempotency at the Stripe boundary. The code below is an illustrative sketch you could start from, and deliberately so: the production source stays at work.

## Money doesn't move in a line

A single `balance` column fails quietly, and in several ways at once. Two movements that should be atomic (take $100 here, note $85 owed there) become two UPDATEs, and a crash between them loses money without a trace. Concurrent writes race unless every path remembers to lock. And when the number looks wrong three months later, there is no history to check it against, because the column is the only record of itself.

Double-entry bookkeeping is the five-hundred-year-old fix, and it maps onto a schema beautifully. Money is never created, destroyed or adjusted; it only moves between accounts. Every movement is one journal entry carrying two or more lines, and the lines of an entry always sum to zero. Take from one bucket, give to another, in the same breath.

Our $100 checkout is one entry with three lines:

| account      | amount   |
| ------------ | -------- |
| `cash`       | +$100.00 |
| `revenue`    | −$15.00  |
| `owed:alice` | −$85.00  |

The negative lines answer the question the balance column can't: whose money is the $100 sitting in `cash`. Fifteen dollars is yours; eighty-five belongs to Alice until you pay her out or give it back. The payout is another entry (`owed:alice` +$85, `cash` −$85), and a refund before payout is the checkout entry mirrored, sign for sign. Nothing is ever edited. A mistake gets a reversing entry, and the wrong turn stays in the book, which is where an auditor (or you, at 2am) wants it.

## Three tables and one invariant

The schema is smaller than people expect.

```elixir
create table(:accounts) do
  add :name, :string, null: false       # "cash", "revenue", "owed:alice"
end

create table(:entries) do
  add :reference, :string, null: false  # your domain identity, e.g. "booking:7f3a…"
  timestamps()
end

create table(:lines) do
  add :entry_id, references(:entries), null: false
  add :account_id, references(:accounts), null: false
  add :amount_cents, :bigint, null: false
end
```

Integer minor units, always: floating-point money is how you end up explaining rounding to an accountant.

The invariant does all the work: within one entry, the lines sum to zero. Posting is a single database transaction that refuses anything else:

```elixir
def post(reference, lines) do
  0 = lines |> Enum.map(& &1.amount_cents) |> Enum.sum()

  Repo.transaction(fn ->
    entry = Repo.insert!(%Entry{reference: reference})

    Enum.each(lines, fn line ->
      Repo.insert!(%Line{
        entry_id: entry.id,
        account_id: line.account_id,
        amount_cents: line.amount_cents
      })
    end)

    entry
  end)
end
```

That bare `0 =` match is doing real work: a set of lines that doesn't balance crashes the caller before a row is written. If you want the database to hold the line too (you do), a Postgres constraint trigger deferred to commit re-checks the per-entry sum, so no future code path can sneak an unbalanced write past the application layer.

A balance is now a query, and only a query:

```elixir
from(l in Line, where: l.account_id == ^account_id, select: sum(l.amount_cents))
```

Cache it if it gets hot, the way you'd cache anything: as a derived value the ledger can always recompute and contradict.

## Idempotency where you meet Stripe

The other half of the pattern lives at the boundary, because payments infrastructure is built on retries. Stripe delivers webhooks at least once, users double-click the pay button, and sometimes your own HTTP call times out so you cannot know whether the money moved. Unguarded, each of those is a duplicate charge or a duplicate payout.

Two guards, one on each side of the wire.

Outbound, every mutating Stripe call carries an `Idempotency-Key` header, and the key is derived from your own record's identity: the booking id for a charge, the transfer record's id for a payout. Retry with the same key and Stripe replays the original outcome instead of moving money again. A fresh UUID per attempt would defeat the whole mechanism, which is precisely what a naive retry wrapper will do to you. One caveat worth knowing: Stripe prunes idempotency keys after 24 hours, so the header protects you through the retry storm, and durability has to come from your own database.

Which is the inbound guard: a unique index on the Stripe object's id in your payment records, and a completion handler that's safe to run any number of times:

```elixir
def complete_checkout(checkout_ref) do
  case Repo.get_by(Payment, checkout_ref: checkout_ref) do
    %Payment{} = payment ->
      {:ok, payment}            # replayed webhook: same answer as before

    nil ->
      record_payment_and_post_entry!(checkout_ref)
  end
end
```

Because the Stripe call and the ledger entry share one domain identity, reconciliation stops being a project. Every Stripe object should sit against exactly one entry, and an entry missing its Stripe counterpart (or the reverse) is one outer join away from being a list on someone's screen.

## What it bought

Stated broadly, because the internals stay internal: refunds and payouts stopped being archaeology. A refund is the mirrored entry plus the Stripe call that shares its reference, and whether a session was already refunded is a single lookup. "What do we owe each coach right now" is a GROUP BY over lines. When finance asks where the money is, the answer is a query whose grand total provably sums to zero, and any imbalance names the entry that caused it.

## Worth stealing

If money in your system moves in more than one direction, start with the ledger; retrofitting one underneath a balance column is miserable, and the schema is three tables. Treat balances as caches over an append-only book, with corrections as new entries, never edits. Derive idempotency keys from domain identity, and own the durable guard yourself: the provider's replay window is a convenience, while your unique index is the actual promise.

One more thing. I wrote the ledger design down before building it, including the tedious parts about processing order and what stops a balance going negative. Six months from now that document will be the only place the reasoning survives. Write yours down.
