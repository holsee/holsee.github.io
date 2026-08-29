---
title: "inventory_es: macros for an event-sourced inventory system"
status: "archived"
start: 2019-11-06
end: 2019-11-06
tags: ["elixir", "oss"]
links:
  - {label: GitHub, url: "https://github.com/holsee/inventory_es"}
highlights:
  - "Training exercise, not a talk: the code I wrote during Greg Young's event-sourcing training day at CodeMesh London, November 2019"
  - "defevent and defcommand: Elixir macros that expand one line into a struct with enforced keys, a typespec and a constructor that mints the id and timestamp, so the message layer of an event-sourced system stops being boilerplate"
cv:
  include: false
draft: true
---

Event sourcing produces a lot of similar-shaped message structs, and
Elixir macros can write the repetitive parts for you. `defevent
CheckedOut, count: integer` becomes a whole module at compile time: the
struct with `id` and `timestamp` prepended, `@enforce_keys` over every
field, a `@type t` with the declared types spliced in, and a `create/1`
that fails loudly if a field is missing. The course's classic inventory
item (create, check in, check out, deactivate) was the example, and the
repo stops at the message layer, which was the point of the exercise.
