---
title: "Faria AI platform"
status: "active"
start: 2023-08-24
tags: ["elixir", "phoenix", "llm", "aws", "security", "evals", "design-docs", "api-design"]
highlights:
  - "Originated in August 2023 as a near-solo LLM framework in Elixir: prompt templates as data, streaming APIs, OTP agents, self-hosted embeddings and vector search, provider fallback"
  - "Re-architected in November 2023 as a platform of named, versioned, auditable AI operations consumed by ManageBac, OpenApply and Atlas, so product teams ship AI features without owning prompts, providers or safety machinery"
  - "Principal architect and co-lead since: a versioned prompt catalogue and 129 releases across two and a half years in production"
  - "Multi-provider: OpenAI, Azure OpenAI, Anthropic direct and via Bedrock, plus Chinese providers for a separate China deployment"
  - "Adversarial red-team evaluation suite and a safeguard middleware layer in front of every operation"
  - "2026: sole-led the AI gateway, a raw-byte relay that holds and signs upstream credentials, tees an audit trail with token usage and pricing off the byte stream, and pre-flights spend; 27 ADRs"
  - "Fleet-wide model migration of 46 production operations off deprecated models, old prompt versions preserved"
cv:
  include: true
  weight: 100
  highlights:
    - "Originated and architected the company's AI platform: versioned, auditable AI operations consumed by every product across OpenAI, Azure, Anthropic, Bedrock and Chinese providers, with a China deployment"
    - "Sole-led the credential-holding AI gateway with byte-stream audit, usage and pricing planes (27 ADRs)"
    - "Red-team evaluation suite and safeguard middleware; 46-operation fleet-wide model migration"
---

The idea that stuck: AI as *operations*. An operation is named,
versioned and auditable, sits behind a simple API, and carries its own
prompt catalogue, context strategies, safeguards and telemetry. Product
teams consume operations; the platform owns providers, cost and safety.
Three years on it fronts every product, in two deployments, with a
couple of hundred versioned prompts and a decision log I still keep.
The gateway came later, for the traffic that never touches an
operation: a raw-byte relay that owns the credentials, watches the
stream go past, and writes down what it cost.
