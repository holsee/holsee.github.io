---
title: "Faria data platform"
status: "archived"
start: 2025-02-12
end: 2026-01-31
tags: ["elixir", "phoenix", "aws", "athena", "sql", "data-platform", "design-docs", "semantic-data"]
highlights:
  - "Founded and architected it in February 2025: the README defining the platform, the Phoenix scaffold, the AWS foundations, and the Athena client library that became the platform's data-access spine"
  - "Bronze, silver, gold on S3 with Athena, Glue and Parquet: raw data from four external source systems standardised into a unified silver layer, then analytics-ready star schemas plus pre-computed aggregates, indicators and signals in gold"
  - "Per-school isolation written down as platform law: the school id is mandatory in every table location, so separation is a property of the storage layout rather than a query someone has to remember"
  - "Oban Pro cron workflows run the ETL; the first production pipeline, attendance, merged three weeks after the platform was founded"
  - "Wrote the data architecture: the cross-source entity reconciliation strategy (co-authored) and the student-attendance star schema with dims, facts, ETL mapping and a worked query index"
  - "Led the versioned data exports that fed one source system's bronze tier, January to September 2025: dated then semantically versioned drops, PlantUML data models and a data dictionary, and a changelog written as a migration guide for the consumers downstream"
  - "Runs in production in three AWS regions as the engine behind the analytics product"
cv:
  include: true
  weight: 85
  highlights:
    - "Founded and architected the group's data warehouse: medallion bronze/silver/gold on S3, Athena, Glue and Parquet, per-school isolation by construction, Oban-orchestrated ETL across four external source systems"
    - "Preceded by a prototype I founded and then argued against: embedded BI over a lake, written up as a negative result that set the platform's direction"
---

The prototype came first: two of us spent the last quarter of 2024
proving embedded BI over a lake end to end, and my write-up said it
worked and was still the wrong experience for schools. Recording that
as a negative result, rather than quietly shelving it, is what set the
direction here. What replaced it, from February 2025, is a warehouse in
layers: raw source data in bronze, standardised and reconciled in
silver, analytics-ready star schemas and pre-computed indicators in
gold, with every school's data separated by construction in the storage
paths. I founded it and set the architecture, a colleague led the
implementation, and the first domain it served was attendance, which is
also the first schema I wrote.
