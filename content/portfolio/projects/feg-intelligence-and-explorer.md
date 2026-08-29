---
title: "Ontology-first warehouse and conversational analytics agent"
status: "active"
start: 2026-06-17
tags: ["clickhouse", "elixir", "liveview", "agents", "llm", "data-platform", "evals", "security", "data-ontology", "semantic-data"]
highlights:
  - "Architect and author of both the data ontology warehouse and the agent on top, fed by another unified cross-system data source"
  - "Second-generation warehouse: ClickHouse, dbt and Airflow shipped as one image; gold layer built backwards from a semantic ontology of 101 object types, 121 links and 20 measures designed for LLM grounding"
  - "Versioned data contracts (v1.0 → v1.2), an append-only data-quality ledger that auto-resolves and reports back to each school, database-per-tenant isolation with split read/PII roles"
  - "Explorer: a conversational analytics agent that never writes raw SQL (the ontology is the allowlist) and reasons only in surrogate keys (\"keys as currency\"), rehydrating names for entitled users in the view layer"
  - "The agent runs on my own Ax framework, vendored into the product (personal library, dependency stated); an evaluation harness built on my own deep_eval_ex drives the real UI with a simulated user and an LLM judge"
cv:
  include: true
  weight: 96
draft: true
---

Gen 2 of the data platform, built in six weeks: the warehouse is
designed from the ontology down so that a language model can be
grounded in it, and the agent on top is constrained by that same
ontology and by a PII plane that gives it keys rather than people.
