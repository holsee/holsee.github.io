---
title: "Data and analytics prototype"
status: "archived"
start: 2024-10-21
end: 2025-01-17
tags: ["elixir", "phoenix", "liveview", "aws", "athena", "data-platform", "design-docs"]
highlights:
  - "Founded the prototype that proved the full analytics chain end to end: source API clients into S3, generated schemas into Glue and Athena external tables, dashboards embedded in a school-facing app behind single sign-on"
  - "Built a declarative test-data composer that generated referentially intact, cross-synchronised datasets across both source products, so the pipeline could be exercised without touching real school data"
  - "Produced the negative result that redirected the platform: embedding a third-party BI tool gave a poor user experience, and the analysis that mattered needed precomputed indicators rather than live query-time aggregation"
  - "That finding is why the platform that followed is a medallion warehouse with curated views rather than embedded BI"
cv:
  include: true
  weight: 55
  highlights:
    - "Founded the data-analytics prototype whose negative result set the direction for the platform that followed (2024)"
    - "Proved the ingestion to warehouse to dashboard chain end to end, then argued against shipping it"
---

A quarter spent proving that something works, and then arguing we should
not ship it. The chain held up: data out of both school products, into
object storage, catalogued, queryable, and on a dashboard inside our own
app. What did not hold up was the experience of using it, and the shape
of the questions schools actually ask, which want an answer already
computed rather than a query fired at click time. I wrote that up as the
recommendation, and the platform we built next took the other road. I
have a soft spot for the prototypes that talk you out of things.
