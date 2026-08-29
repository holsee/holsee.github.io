---
title: "codebase-memory-mcp: Elixir support for a C code-intelligence engine"
status: "paused"
start: 2026-07-23
end: 2026-07-26
links:
  - {label: "Source", url: "https://github.com/DeusData/codebase-memory-mcp"}
tags: ["oss", "mcp", "elixir", "agents", "semantic-data"]
highlights:
  - "Contributed Elixir semantic resolution to DeusData's code-intelligence engine, a pure-C binary that indexes a repository into a knowledge graph and answers structural queries over MCP"
  - "A resolver ladder built a phase at a time: scopes, aliases and imports, name/arity identity across pipes, captures and default args, cross-file fallback, use-macro tables, protocol dispatch, defdelegate edges, behaviour and impl linkage, and Struct nodes from defstruct"
  - "Then an F1 to F9 field-hardening campaign, validated against a 1,240-file production Phoenix application: every defect reproduced against a from-scratch index before it was written up, artefact findings discarded"
  - "Impossible call edges from typespecs and struct-field reads went 174 to zero on that application, and grouped multi-line alias and import expansion took resolved imports from 7 to 13"
  - "Also Phoenix router extraction including resources expansion and if/unless descent, index invalidation on binary upgrade via an indexer fingerprint, Cypher WITH-clause scalar grouping, and OTP entry-point flagging from behaviour tables"
  - "Four days of work on a fork, with an upstream submission plan written alongside them; merge status is the maintainers' to report"
cv:
  include: true
  weight: 55
  highlights:
    - "Contributed Elixir semantic resolution and a nine-defect hardening campaign to DeusData's C code-intelligence MCP engine, validated against a 1,240-file production Phoenix application (impossible call edges 174 to zero)"
---

The engine is DeusData's, a single static C binary that indexes a
repository into a knowledge graph and answers structural queries over
MCP for coding agents. It had no semantic resolution for Elixir, so I
wrote one on a fork, taking the awkward parts of the language a phase
at a time, from aliases and imports up through name/arity identity,
use-macro injection, protocol dispatch and behaviour linkage. Then I
pointed the result at a 1,240-file production Phoenix application,
reproduced nine defects against a clean index before writing any of
them up, and fixed the lot; impossible call edges dropped from 174 to
zero. Four days on someone else's codebase, which is a good way to find
out how well you actually know a language.
