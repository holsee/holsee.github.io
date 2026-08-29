---
title: "pinch: web scrapers defined in YAML"
description: "Job definitions in YAML, targets with named captures that feed the next job's parameters, post-ops as module-function-args, and one nasty encoding bug."
tags: [work, elixir, oss]
draft: true
---

I needed structured data out of a legacy web app that has no API and isn't going to get one. The tempting thing is to write a scraper. The thing I actually wanted was to *not* write a scraper every time: describe the extraction as data and let one small engine run it. So `pinch`: a web scraper whose jobs are YAML, whose pipeline is captures feeding parameters, and whose entire plugin system is the BEAM's own idea of a function (a module name, a function name and some arguments). That last part is the bit I'd steal for anything.

## A job is a value

A pinch job says where to go, how to authenticate, and what to pick out of the page. Roughly (I've swapped the real host and credentials for placeholders; the originals are neither):

```yaml
base_url: "http://example.internal/app/"
auth:
  username: "..."
  password: "..."
path: "records/edit?action=show&id=$REC"
target:
  elem: "a"
  attribute: "href"
  contains:
    - "zip"
```

That's a whole scraper. `Pinch.execute/1` builds a Tesla client from `base_url` and `auth`, does the `GET`, and on a `200` pipes the body straight into Floki:

```elixir
# lib/pinch.ex (the happy path)
case HTTP.get(client, path) do
  {:ok, %{status: 200, body: body}} -> Floki.parse(body) |> extract(job)
  {:ok, %{status: code}} -> Logger.warn("non-200: #{code}"); {:error, status: code}
end
```

and the target picks a value: `Floki.find(page, elem)`, then either an attribute or the text. None of that is clever, and the point is elsewhere: the job is *data*. You build a job, you map a list of jobs, and `Task.async_stream` (the standard library's "run this function over a list concurrently, with a cap on how many at once") fans them out across every core. The scraper stopped being code and became a value I could generate.

## The bit that makes it a pipeline: captures feed the next job

Real scraping is never one page. You hit an index to get a list of ids, then hit a detail page per id. So a target can carry a named capture, and the captured value comes back keyed with a `$` in front of it:

```elixir
# lib/pinch/job.ex (captures re-keyed with a leading $)
Regex.named_captures(regex, text)
|> Enum.map(fn {k, v} -> {"$#{k}", v} end)
```

That `$` is deliberate and load-bearing. The path in the job above is `records/edit?...id=$REC`. So the output of one job (a set of `$REC` values scraped from an index) feeds straight into the `params` of the next, hydrated by name. `apply_args` takes a template job and a bag of `$`-prefixed captures and stamps out one concrete job per id. The getting-started flow is literally: run the index job, get the ids, load the detail job as a template, map the ids over it, stream the lot. The captures and the parameters share a namespace on purpose, so chaining is substitution, not glue code.

## Post-ops are just module, function, args

Scraped text is filthy: trailing brackets, wrong case, stray whitespace. Rather than bake a cleaning DSL into pinch, a target names a plain Elixir MFA to run on the extracted value. MFA is module, function, arguments: on the BEAM every function is addressable by that triple, and `apply(m, f, a)` calls it, so a triple sitting in a YAML file is a callable value the moment it's loaded:

```yaml
post_op: [Elixir.String, replace, [")", ""]]
```

`parse_mfa` resolves those atoms and returns a closure that prepends the scraped value as the first argument, and `extract` just `apply`s it:

```elixir
{m, f, a} = target.post_op.(value)
apply(m, f, a)
```

So `[Elixir.String, downcase, []]` lower-cases a field, `[Elixir.String, replace, [")", ""]]` strips a bracket, and, because it's any MFA, you can point it at your own module when the standard library runs out. No plugin system, no callback registry. The BEAM already has one: a module, a function, and some arguments. In most languages this is the point where you write a registry of named cleaners, or a tiny expression language, and then maintain it. Here it's three atoms and `apply/3`.

## The encoding bug I earned

Here's the war story the commit log remembers. The target app served pages that claimed one encoding and delivered another, so some scraped fields were invalid UTF-8, and invalid UTF-8 doesn't travel: it blows up the moment you try to JSON-encode it or write it anywhere. The fix is a post-op of its own, and it's the sort of thing you only write after it's bitten you:

```elixir
# lib/pinch/sanitise.ex
def ensure_valid_utf8(binary) do
  # re-decode the raw bytes as Latin-1 when they aren't valid UTF-8
  :unicode.characters_to_binary(binary, :latin1)
end
```

It reinterprets the bytes as Latin-1 and re-emits them as clean UTF-8. It's not principled (the app's bytes weren't really Latin-1 either), but it's the pragmatic rescue for "this page lies about its charset and I still need the data". Every scraper of a legacy system grows one of these eventually. Mine lives in the post-op list next to `downcase`, which feels about right: cleaning a value and rescuing its encoding are the same kind of job, applied the same way.

## If you're doing this

Make the scraper's orders data, not code, and two things fall out for free: you can generate jobs instead of writing them, and you can chain them by making captures and parameters share a namespace. Then let the value be dirty and clean it with plain functions on the way out. The engine stays small; the YAML does the varying.
