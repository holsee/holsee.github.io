---
title: "Product AI agent and MCP doctrine"
status: "paused"
start: 2026-02-06
end: 2026-03-20
tags: ["elixir", "liveview", "mcp", "agents", "llm", "evals"]
highlights:
  - "Architect and lead, over six weeks, of a role-routed in-product assistant (student, teacher, parent, staff) over a fleet of 12 in-app MCP servers"
  - "Authored the MCP tool-design doctrine: intent over CRUD, four to eight tools per server, per-role server variants, resources for ambient context"
  - "Runs on Ax, my own agent framework (personal library, dependency stated); China mode swapping in Qwen; per-role evals on deep_eval_ex, my own DeepEval port"
cv:
  include: true
  weight: 70
draft: true
---

Six weeks that produced a working agent and, more durably, a doctrine
for how many tools a server should expose and why. Tool routing
degrades as the tool count grows, so each server carries four to eight
intent-shaped tools and each role sees only its own servers.
