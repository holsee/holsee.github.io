---
title: "Rebuilt with Cherry"
description: "This site now builds with Cherry, an Elixir static site generator, after a decade on Octopress."
tags: [meta, elixir, cherry]
---

After a decade frozen on Octopress, this site is now built with
[Cherry](https://cherrybomb.dev), a static site generator written in Elixir.

The migration was done by an AI agent driving the `cherry` CLI: every command
speaks JSON, the verifier (`cherry check --strict`) turned 41 content problems
into a fixable list, and the whole thing built clean on Windows.

Fitting, given how many posts here are about Elixir in the first place.
