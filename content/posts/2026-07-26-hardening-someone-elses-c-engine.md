---
title: "Teaching a C code-graph engine Elixir"
description: "Adding Elixir resolution to a pure-C code-intelligence engine, then pointing it at a 1,240-file Phoenix app: 174 call edges to things that can't be called, 47 routes the graph couldn't see, and the discipline of saying which numbers you measured."
tags: [personal, elixir, mcp, agents, oss, semantic-data]
---

A code-intelligence engine is only as useful as its resolution. Tree-sitter will hand you the syntax of any language for free; what an agent needs is to know that *this* call in *this* file refers to *that* function in *that* module, with *that* arity. Four days this week went into giving DeusData's [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) that for Elixir, and then proving it against a real application.

The engine is a pure-C, zero-dependency code-intelligence server for coding agents: it indexes a repository through vendored tree-sitter grammars into a persistent knowledge graph (functions, modules, call chains, HTTP routes), answers structural and Cypher queries in under a millisecond, ships as one static binary, and exposes its graph over MCP. It has a semantic tier for languages where it can do real resolution, and Elixir wasn't in it. It's a serious piece of software written by other people, and I wanted it to understand Elixir properly.

## where Elixir stops being simple

The resolver went in as a ladder, each rung a reviewable step, and the rungs are roughly the order in which Elixir stops being easy to resolve. Aliases and imports, so a bare `foo()` and a qualified `Mod.foo()` both land somewhere. Name-and-arity identity, because `foo/1` and `foo/2` are different functions, and pipes, captures and default arguments all change the arity you're looking for. Then the part that makes Phoenix interesting: `use` macros and framework injection, where a module acquires functions that appear nowhere in its source text, and protocol dispatch and behaviour callbacks, where the thing you call is declared in one module and implemented in another. Get those wrong and the graph is confidently, silently incomplete.

## then point it at something real

A resolver that passes its own tests has proven very little. So I indexed a 1,240-file production Phoenix application I know well and wrote a bug report against the graph. The report's first section lists what was verified correct, so nobody chases it; every finding after that was reproduced against a from-scratch index, and anything that turned out to be stale state was discarded rather than reported. Nine defects survived. Two of them are worth telling.

The first is impossible call edges. The graph contained 174 call edges to things that cannot be called. A typespec like `@spec f(User.t()) :: :ok` was producing a call edge to `User.t/0`; a struct-field read like `user.name` was producing an edge to a function called `name`. Each one is a plausible-looking lie an agent would follow. The fix is in the extractor: typespecs produce `USES_TYPE` edges instead, so the types you reference are in the graph as relations rather than noise, and field access produces nothing. On the corpus: 174 before, 0 after.

The second is routes. The router extraction found 0 of the app's 48 routes, because Phoenix routes are macros. `resources "/users", UserController` expands to seven routes that never appear as text; routes declared inside `if` and `unless` blocks were skipped entirely; dashboard mount points weren't recognised as routes at all. After proper macro expansion and descent into conditionals: 47 of 48. The one still missing is a lesson in itself, and it's logged as a target rather than quietly rounded up.

The other seven were the same shape: a grouped multi-line `alias` that was being missed, framework-invoked callbacks not flagged as entry points, cluster detection that gave different answers on every run. Resolved imports on one controller went from 7 to 13. Every number was measured on the same app against a stated baseline build and a stated final build, so anyone with the app can rerun the comparison.

## measured, or target

Three documents came out of it: the bug report, a before-and-after field report, and an install-and-verification guide. The guide marks every number as either *(measured)* or *(target)*. A measured number is one I ran and can reproduce. A target is what a fix should achieve but hasn't been re-measured in that configuration. Mixing the two is how a report gets a reputation, and there's a commit in the log titled "correct IMPORTS-edge overclaim" for the one time I mixed them: I had overstated what the imports work delivered, noticed, and corrected it in the record rather than quietly amending the report. The willingness to write that commit message is most of what "measured" means in practice.

One more piece of hygiene you owe a C codebase: ThreadSanitizer soak runs and pathological-input testing before any of it was offered upstream. The README now lists Elixir among the languages at the engine's semantic tier.

## what I don't know

Merge status. There's a submission plan and the work was shaped for someone else's review from the start, but whether and how much has landed in upstream main is the maintainers' to report, not mine. Indexing `.heex` templates was deferred; whether it becomes a follow-up is open.

The engine was good before I touched it. What I added is a language, and nine fewer ways to be confidently wrong about a Phoenix app.

## Where to look

- Upstream: https://github.com/DeusData/codebase-memory-mcp
- Fork with the Elixir resolver and the field-hardening branch: https://github.com/holsee/codebase-memory-mcp
