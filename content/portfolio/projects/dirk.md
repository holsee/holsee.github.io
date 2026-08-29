---
title: "dirk: an ontology-backed entity resolution engine"
status: "paused"
start: 2026-05-16
end: 2026-05-25
tags: ["go", "algorithms", "data-ontology", "semantic-data"]
highlights:
  - "An entity resolution engine in Go over in-process DuckDB: ingest, project, resolve, derive. Rows from heterogeneous CSV sources are projected into a declarative ontology, resolved into canonical entities with row-level provenance, and every merge can be explained end to end"
  - "The ontology is the product: object types, properties, identifiers and links declared in YAML, each property carrying its own comparator and weight, hot-reloadable overlays so a new type lands without a restart, and a maritime fixture proving a new domain in about half an hour"
  - "Matching that knows the difference between missing and wrong: blocking to keep comparisons finite, Jaro-Winkler and exact comparators returning NaN for absent fields, a minimum-evidence floor against the single-matching-name trap, identifier short-circuits, union-find clustering and trust-ranked value resolution"
  - "Typed links materialised between entities, a graph canvas with no silent truncation, and a six-step onboarding wizard that runs the whole pipeline from a dropped CSV"
cv:
  include: true
  weight: 70
  highlights:
    - "Built an ontology-backed entity resolution engine in Go with explainable merges and row-level provenance (2026)"
draft: true
---

Ten days in May, in Go, on a thing I had wanted to build for a while: a
data layer where the ontology is declared rather than coded, duplicates
are resolved with a score you can read, and every canonical field still
points back at the row it came from. Public sanctions data was the test
adversary, because it is messy in exactly the ways that matter. The
algorithms are decades old; the part that took thought was the
arithmetic of absence, and that got [a post of its
own](/deciding-two-rows-are-the-same-thing/).
