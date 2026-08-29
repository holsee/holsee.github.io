---
title: "ax: an Elixir agent framework and MCP library"
status: "active"
start: 2026-01-15
tags: ["elixir", "otp", "agents", "mcp", "llm"]
highlights:
  - "An LLM agent framework built on OTP primitives: agents are supervised processes, sub-agents run under a DynamicSupervisor, LLM calls sit behind a circuit breaker, and a human-in-the-loop pause persists the agent's state so it can be resumed"
  - "ax_mcp, a server and client library covering MCP spec revision 2025-11-25: a declarative tool, resource and prompt DSL, Streamable HTTP with SSE resumability, stdio, OAuth 2.1 bearer validation, MCP Apps, Phoenix Plug integration, and an in-process transport for tests"
  - "ax_audit, a Phoenix app giving observability over AI sessions, plus a demo app that keeps the framework honest"
  - "Pluggable LLM adapters (Claude, OpenAI, Ollama or your own), typed tool registration with render types for UI, a Skills system with progressive disclosure, streaming with event callbacks, OpenTelemetry tracing"
  - "Built from January to July 2026 against a numbered feature-spec system with per-feature status tracking"
cv:
  include: true
  weight: 90
  highlights:
    - "Wrote ax, an Elixir LLM agent framework on OTP primitives, with a full MCP server and client library (2025-11-25 spec, OAuth 2.1, SSE resumability) and an AI-session observability app alongside it"
draft: true
---

Six months of my own time on an agent framework built the way I would
build any BEAM service. Agents are supervised processes, sub-agents run
under a DynamicSupervisor, LLM calls sit behind a circuit breaker, and
pausing for a human writes the agent's state down so it can pick up
again later. The MCP library beside it implements the 2025-11-25
revision properly, down to SSE resumability and an in-process transport
so the tests never need a socket. I have been pointing coding agents at
it while building it, which is a decent way to find out whether an agent
framework is any good. Open source, coming soon.
