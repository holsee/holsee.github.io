---
title: "Inbound data-ingestion platform"
status: "archived"
start: 2022-05-30
end: 2023-01-13
tags: ["elixir", "otp", "phoenix", "liveview", "postgres", "distributed-systems", "api-design"]
highlights:
  - "Led the build, in a two-person team, of an ingestion platform over an exam board's inbound data feed"
  - "Designed the ingestion protocol: prioritised, idempotent, ack/nack changeset consumption with type-based ordering, batch acknowledgement and retry-on-error polling"
  - "Modelled the ~25-entity domain and made portfolio-template matching fast with concurrently-refreshed, indexed materialised views"
  - "Ran a Commanded/EventStore CQRS spike first; the event-sourcing findings shaped the Event/Command patterns in the main build"
  - "Prototyped the school-facing assembly UI in LiveView, one supervised process per school project"
cv:
  include: true
  weight: 55
  highlights:
    - "Led a two-person build of a prioritised, idempotent, ack/nack ingestion platform over an exam board's inbound data feed, with a ~25-entity domain model and materialised-view matching"
draft: true
---

Ingestion sounds dull until the upstream is a database you do not
control, publishing changesets you must never lose and never apply
twice. The protocol I designed at work pulls them in priority order,
acknowledges in batches, and stays idempotent the whole way down. We
spiked event sourcing properly before committing: the spike stayed a
spike, and the patterns it proved carried into the build.
