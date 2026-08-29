---
title: "etl: errors as values in batch imports"
description: "A raise three hours into a data import throws away every row before it. etl is the small Elixir library I wrote at work to stop that: the whole job is a struct of functions, and stage failures travel through the pipeline as values you collect at the end."
tags: [work, elixir, sql, api-design]
draft: true
---

The worst way for a data import to fail is loudly, at row 400,000. Somewhere deep in a legacy table there's a row with a NULL where no NULL should be, the transform raises, the process dies, and every row before it is either wasted work or, worse, half-committed state. Run it again and you get to wait for the same crash. What you want from a batch job is the boring outcome: the good rows are in, the bad rows are in a list, and the list says which stage rejected each one, with what input, and why.

After the second or third import job at work (rows out of one database, reshaped, loaded into another) I noticed I was rebuilding the same scaffold every time: connect, query, map over rows, insert, apologise when it crashes. So I pulled the scaffold out into a small library called etl. This post is about the library, because the pattern in it is the interesting bit.

## the whole job fits in a struct

An etl job is a struct of four fields, and the extract is data before anything runs:

```elixir
# lib/etl.ex
defstruct [:driving_query, :extract, :transform, :load]

# ...

@type query :: {:file, sql_file_path()} | {:table, table_name()} | {:sql, sql()}
```

`{:table, name}` selects everything from a table. `{:file, path}` keeps a big query in a `.sql` file, where it can be reviewed as SQL instead of a string buried in Elixir. `{:sql, query}` is the escape hatch. The transform is a function from a row (a plain map, columns zipped to values) to whatever shape the destination wants, and the load is a function that puts each result somewhere, a `Repo.insert` usually.

Connection options live outside the struct on purpose. `ETL.exec(job, connection_opts)` means the same job definition runs against a staging copy, then production, then next month's other source database, with nothing edited. The job is a value; where it points is a parameter.

In most ecosystems this is the point where a batch framework arrives, with its job classes, step definitions and a scheduler to configure. Here a job is a struct (a map with a fixed set of keys) holding a query and three functions, and the whole engine fits on one screen.

## the driving query curries the stages

The migrations I keep meeting have a shape: one query decides the scope (which records move) and each row of *that* result wants its own full extract-transform-load pass, parameterised by the row. So the struct's first field:

```elixir
# lib/etl.ex
def exec(%__MODULE__{driving_query: driving_query} = job, opts) do
  driving_query
  |> q!(opts)
  |> Enum.map(fn mapping ->
    # Curried ETL functions based on driving query mapping result
    extract = job.extract.(mapping)
    transform = job.transform.(mapping)
    load = job.load.(mapping)
    exec(extract, transform, load, opts)
  end)
end
```

With a driving query present, each stage you supply sits one level higher: a function that takes a driving row and returns the stage function for that row. The extract can build a different query per record, the transform can close over the driving row's ids, and the inner `exec` never knows the difference. Currying is doing all the work here, and it fell out of the design rather than being designed in, which is the nicest way to get it.

## failures ride the pipeline as values

A single pass is an eager pipeline with every stage call wrapped:

```elixir
# lib/etl.ex
extract
|> q!(opts)
|> Enum.map(&(stage_handler(:transform, transform, &1)))
|> Enum.map(&(stage_handler(:load, load, &1)))
```

and `stage_handler` is where the crash-at-row-400,000 problem goes away:

```elixir
# lib/etl.ex
defp stage_handler(_stage, _func, {:error, _, _} = e), do: e

defp stage_handler(stage, func, arg) do
  try do
    func.(arg)
  rescue
    error ->
      {:error, {stage, arg}, {error, __STACKTRACE__}}
  end
end
```

Two clauses. If a value is already an error triple, the stage steps aside and passes it along, so a row that failed in transform never reaches load; the error just rides the rest of the pipeline to the results. Otherwise the stage runs, and a raise becomes a value carrying the stage name, the exact input, the error and the stacktrace. (`__STACKTRACE__` is new in Elixir 1.7 and this is precisely the job it exists for.) That triple is everything you need to reprocess only the failures.

At the end of a run, `ETL.errors(results)` filters the oks away and hands back the failures; give it a function and it attaches your own metadata per failure, the source record's id say, so the report reads in domain terms.

I'm as fond of let-it-crash as the next Erlang admirer, but it's a philosophy for long-lived processes, where a supervisor restarts you into a known good state. A batch job has no good state in the middle. Restarting means starting over. So here a crash is demoted to data, the run finishes, and the failure list is the deliverable rather than the obituary.

## eager on purpose

The README carries one implementation note I insist on keeping: eager query execution only. `q!` runs the query through the mariaex driver and materialises every row before the first transform fires, and the pipeline after it is `Enum.map`, deliberately. The tempting move is swapping in `Stream.map` so the library looks lazy, and that would be a small lie: the memory bill for the result set was already paid inside `q!`, and lazy stages after an eager fetch hide where the cost lives without removing any of it. If a table is too big to hold, the fix belongs at the extract (a cursor, paging), and until the library does that for real I'd rather the docs say eager than the types imply otherwise.

## what to take from it

When the work is batch, treat errors as data: capture stage, input, error and stacktrace, keep going, and collect at the end. It turns "the import crashed" into "the import finished with 14 rejects, here they are", and the second sentence is the one your Monday wants.

And make the job a value with its environment as a parameter. A struct of functions you can point at any connection is reusable in a way a script never is. Just be truthful about where the eagerness sits; laziness that starts after the fetch is decoration.
