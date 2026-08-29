---
title: "Safeguarding and wellbeing product (pre-pilot)"
status: "active"
start: 2026-04-22
tags: ["elixir", "phoenix", "liveview", "postgres", "agents", "asdlc", "security"]
highlights:
  - "Sole author, empty repo to v0.5.0 in 30 days, by running my own agentic SDLC: seven named sub-agents, around 28 human-gated sprints, agents report and humans merge"
  - "1,185 ExUnit tests and 205 Playwright specs"
  - "Append-only chronology enforced at three layers down to PostgreSQL triggers: an audit trail whose events can be edited is not an audit trail"
  - "Consent scopes as a first-class primitive: out-of-scope events are elided, never leaked"
cv:
  include: true
  weight: 90
  highlights:
    - "Sole-authored a safeguarding product from empty repo to v0.5.0 in 30 days via my own agentic SDLC: 1,185 unit and 205 E2E tests, append-only integrity enforced to Postgres-trigger depth"
draft: true
---

The proof that the methodology works: a whole product, in a domain
where integrity is the feature, built by one person directing a small
team of agents with a human gate on every transition. Append-only
chronology and consent scopes came first, because in safeguarding the
audit trail is the product.
