---
title: "ash_athena: an AWS Athena data layer for Ash"
status: "paused"
start: 2025-11-30
end: 2025-12-09
tags: ["oss", "elixir", "aws", "athena", "sql", "data-platform"]
highlights:
  - "Author of AshAthena.DataLayer, an Ash Framework 3.x data layer over AWS Athena: full SQL translation, streaming results and partition optimisation, read-first by design"
  - "Analytics extensions beyond core Ash: group_by/2, aggregate/4 and having/2 on Ash queries, alongside filtering, sorting, pagination, calculations, composite keys and runtime configuration"
  - "Ten days from empty repo to working data layer, with GitHub's Copilot coding agent contributing under my direction"
cv:
  include: true
  weight: 60
draft: true
---

I wanted Ash resources to sit on top of AWS Athena, so I spent ten days
in my own time at the turn of December 2025 building the data layer for
it. A resource declares an athena block, and the filter, sort,
calculation and pagination surface it uses gets translated into Athena
SQL, with streaming results and partition-aware queries; writes stay out
of scope, which suits a query service sitting over S3. The part that
goes past Ash itself is the analytics layer, because core Ash has no
group_by or having and an analytics engine needs both. A handful of the
commits came from GitHub's Copilot coding agent working under my
direction, which made the build an experiment in two things at once.
