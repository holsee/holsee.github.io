---
title: "Spotlight school analytics"
status: "active"
start: 2025-01-24
tags: ["elixir", "phoenix", "liveview", "aws", "athena", "data-platform", "llm", "agents", "semantic-data"]
highlights:
  - "Founded it in January 2025: a product vision document and a draft attendance star schema landed in the repo before any application code"
  - "Top author from the first commit through to March 2026; in production across three AWS regions"
  - "Attendance first (report views, student detail, insight cards for declining and partial absence, alerts, trends), then grades and assessments with historical comparison across terms; sole author of the design docs for two of the report-view epics"
  - "Came up with and implemented the dynamic insights functionality: statistical models computed in the warehouse (consecutive-absence blocks, mixed-attendance detection, month-over-month decline with severity bands, and a sliding-window early-warning score with an acceleration term and configurable weights and thresholds) that provide intelligence over the data in a reliable, predictable way, producing the higher-level signals that drive user insights and the LLM-based interaction on top"
  - "Top author of the query layer the product reads the warehouse through: Athena query module, SQL parser, SQL protection, results parser; sole author of its AWS module"
  - "\"Ask Spotlight\": natural-language questions answered over a semantic layer and data providers with a structured-metadata context builder, merged July 2025"
  - "Ask Agent: an OTP skills system with a session process per conversation, a resumable matcher for filter extraction and a block protocol for the UI, merged January 2026"
  - "Every model call goes through the company AI platform rather than a provider SDK, so usage, auditing and token cost sit in one place"
cv:
  include: true
  weight: 90
  highlights:
    - "Founded the school analytics product on the group's data warehouse: attendance and grades domains, curated report views, in production across three AWS regions"
    - "Conceived and built its dynamic insights: statistical models in the warehouse (sliding-window early-warning scoring with acceleration, month-over-month decline, absence-pattern detection) providing reliable, predictable intelligence over the data, the higher-level layer that drives user insights and the LLM interaction"
    - "Built its AI line end to end: natural-language querying over a semantic layer, then an OTP agent skills system, with answers grounded in pre-computed warehouse figures"
---

I founded Spotlight in January 2025, and the first things in the repo
were a product vision document and a draft attendance schema, before
any application code. It reads the warehouse rather than the source
systems, so the numbers a school sees were computed before anyone
asked for them. The AI line is the part I care most about: solid
mathematics first, language model second, so an answer traces back to
figures the warehouse already holds.
