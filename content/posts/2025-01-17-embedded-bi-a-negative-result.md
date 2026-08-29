---
title: "Embedded BI: twelve weeks to a negative result"
description: "Two of us spent a quarter proving an analytics chain end to end, then argued against shipping its headline technology. Why that's a good outcome, and the synthetic-data composer that turned out to be the most reusable thing in the prototype."
tags: [work, aws, athena, data-platform, bake-off]
draft: true
---

Twelve weeks, two of us, and the last commit landed today. The conclusion is that the headline technology is the wrong one. I'm fond of this result, and I want to write down why before the next thing starts.

## the brief

Prove, end to end, that data from two of our products can be pulled out, landed in an analytics substrate, and served back to customers as dashboards inside an application they already log into. The bet was embedded BI: take a hosted business-intelligence product, embed its dashboards in our own app, and let people explore.

The prototype works. That's not the interesting bit.

## what we built

The source side came first, deliberately: API clients for both products, and docs on their entities and how to poll and sync them. If you can't get the data out reliably, nothing downstream is worth prototyping.

From there the chain ran: source APIs into object storage with generated schemas, a catalogue and external tables over it so the data is queryable with plain SQL, and the BI product's dashboards embedded inside a customer-facing LiveView app behind our single sign-on. My colleague handled provisioning, deprovisioning and multi-instance support; I did the source clients, the embedding and the query tooling.

## the composer

The most reusable thing in the prototype isn't the dashboards. It's the data.

You can't demo analytics on an empty warehouse, and real customer data has no business in a prototype. So I built a declarative test-data composer: describe what you want and it generates datasets for both products that are referentially intact within each system and cross-synchronised between them, then emits CSV, which is what the external tables want.

Cross-system integrity is the hard part and the whole point. A synthetic dataset where the two source systems disagree about the same entities tells you nothing about joins, and joining the two systems was much of the point. The composer takes a description of the shape (how many organisations, how many people per organisation, which records reference which) and produces both sides from one model, so an identifier on one side always has its counterpart on the other. It survives the pivot below unchanged, and it's the page I'd point anyone at.

## the verdict

By this month the analytics questions were real ones, written as SQL against the substrate. And by then the conclusion about the presentation layer was already clear:

1. The experience is a BI tool's experience, not the product's. A customer doesn't want a dashboard builder. They want to be told what to look at.
2. The interesting answers aren't aggregations you can drag onto a chart. The signals people actually want are computed, with a definition someone owns, and they need to be pre-computed by the platform rather than derived ad hoc in a visual layer.

Twelve weeks of prototype to find out the headline technology is the wrong one is a good trade against twelve months of product built on it.

## what survives

The substrate. Object storage, catalogue and external tables carry forward unchanged; the presentation layer is what gets replaced. The SQL from the last two weeks is the seed of the first real analytics. The composer comes too.

I have a soft spot for the prototypes that talk you out of things. The brief said prove it works, and we did, and the most valuable line in the write-up is the one that says don't ship it like this.
