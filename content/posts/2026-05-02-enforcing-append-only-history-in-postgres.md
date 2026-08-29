---
title: "Append-only history that Postgres enforces itself"
description: "Certain rows, once written, must never change, and an application-level promise can't hold that line. Here's the pattern that can: REVOKE the verbs, a BEFORE UPDATE OR DELETE trigger that refuses everyone, corrections as superseding rows, an ExUnit test that asserts the exception, and the deliberate escape hatch GDPR demands."
tags: [work, postgres, sql, security]
draft: true
---

A product I'm building at work just now has a hard requirement: certain records, once written, must never change. The history they form is only worth something if nobody can quietly rewrite it, and "the application promises not to" is a hope with a nice suit on. So this week I pushed the promise down through the stack until it landed in the only place it can actually be kept, and the pattern is worth walking through, because it travels to any system that needs an honest history: audit logs, financial ledgers, medical trails, anywhere "what happened" outranks "what we'd prefer had happened".

## Why the application can't keep this promise

The application layer can be perfectly well behaved. Ours is: the context module exposes two write functions and both are inserts. Code review watches for stray `Repo.update` calls. You can even teach your linter to reject them at compile time, which we did, and it's worthwhile.

All of that governs code that exists today and plays fair. It says nothing about the `update_all` in next year's backfill migration, the raw SQL somebody reaches for under deadline, a call assembled with `apply/3` that no static check can see, or a psql session at 2am during an incident. Every one of those walks straight past the application and talks to the same table. The paths only converge in one place, so that's where the invariant has to live. Postgres it is.

## First layer: take the permission away

The cheapest enforcement is a grant. The application's role simply doesn't get the verbs:

```sql
REVOKE UPDATE, DELETE, TRUNCATE ON entries FROM app_rw;
GRANT SELECT, INSERT ON entries TO app_rw;
```

Now the ORM can generate whatever it likes; the connection isn't allowed to say it. Two lines, and the entire class of "some future application bug mutates history" is closed. I'd do this for every append-only table on principle.

It isn't sufficient on its own, though. Grants don't bind the table's owner, migrations usually run *as* the owner, and anything superuser-shaped ignores them entirely. Which is exactly the hole a trigger fills.

## Second layer: a trigger that says no to everyone

```sql
CREATE FUNCTION entries_no_mutate() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'entries is append-only: % is forbidden', TG_OP
    USING ERRCODE = 'P0001';
END;
$$;

CREATE TRIGGER entries_append_only
BEFORE UPDATE OR DELETE ON entries
FOR EACH ROW EXECUTE FUNCTION entries_no_mutate();
```

A `BEFORE` trigger fires for every role, owner included. A superuser can still drop it, but that's rather the point: mutating history now requires visible DDL (a deliberate act that lands in change management) instead of one stray statement. The same goes for legitimate maintenance. If a future migration must backfill a column on existing rows, it drops the trigger, mutates, and recreates it inside the one transaction, which turns "we edited history" into something you can only do on purpose, in a reviewed file.

The trigger also caught something I hadn't thought about. Our author column is a foreign key with `ON DELETE SET NULL`, and that cascade arrives at the table as an UPDATE, which the trigger blocks. Deleting a user who has ever authored an entry now fails. For this product that's the correct behaviour (history outlives its authors), but I found it through a failing test, and it's the kind of interaction you want to find on purpose. Cascades are mutations too.

## Corrections are new rows

Append-only doesn't mean mistakes are permanent; it means fixing one is an insert. Each correcting row points at the row it supersedes:

```sql
ALTER TABLE entries
  ADD COLUMN supersedes_id bigint REFERENCES entries (id);
```

An "edit" writes a full replacement row carrying its own author and its own timestamp. Reads that want current state go through a view:

```sql
CREATE VIEW current_entries AS
SELECT e.*
FROM entries e
WHERE NOT EXISTS (
  SELECT 1 FROM entries s WHERE s.supersedes_id = e.id
);
```

You get both stories. The view answers "what do we believe now"; the base table answers "who believed what, and when". The original row still says what it said, with the correction sat alongside it. A history you can edit is just a draft.

## The test is the good bit

Because the guarantee lives in the database, you can test the guarantee itself rather than the application's good manners:

```elixir
test "UPDATE is refused at the storage boundary", %{entry: entry} do
  assert_raise Postgrex.Error, ~r/append-only/, fn ->
    entry
    |> Ecto.Changeset.change(%{note: "tampered"})
    |> Repo.update()
  end
end

test "raw SQL is refused too", %{entry: entry} do
  assert_raise Postgrex.Error, ~r/append-only/, fn ->
    Repo.query!("UPDATE entries SET note = 'x' WHERE id = $1", [entry.id])
  end
end
```

There is something deeply satisfying about a test whose passing condition is an exception from the database. It exercises the same path any future bypass would take, so if someone removes the trigger in a careless migration, CI goes red before the audit does.

## The escape hatch you owe the lawyers

An append-only table with no lawful-erasure story is its own bug. GDPR's right to erasure doesn't care how proud you are of your triggers, so deletion has to exist, as a narrow, audited path rather than an ambient capability. The shape I like is a separate Postgres role that only one reviewed job connects as, plus a trigger that yields to a transaction-scoped setting:

```sql
IF current_setting('app.allow_mutation', true) = 'on' THEN
  RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END IF;
```

The erasure job runs `SET LOCAL app.allow_mutation = 'on'` inside its transaction, does its narrow work, and the permission evaporates at commit. `SET LOCAL` can't leak past the transaction, the app never holds the role's credentials, and every use is one code path you can log and review. Deliberate on every axis, which is the property an erasure mechanism should have.

## Where the requirement belongs

The transferable rule: an integrity requirement belongs at the lowest layer that can enforce it. Politeness in the context API, checks in the linter, grants on the role, triggers at the storage boundary: each layer catches what the ones above it can't reach, and only the bottom one holds against every caller. If your spec contains the words "must never change", write the trigger the same day you write the table, test it through the front door with an `assert_raise`, and design the erasure path in the same sitting. History you can't rewrite is only trustworthy if you also know exactly how, and by whom, it lawfully can be.
