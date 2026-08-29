---
title: "See D12: keep a numbered decision log"
description: "The most expensive argument on a fast-moving platform is the one you have twice. What earns an architecture decision record, the one-page form that survives contact with a deadline, and what a numbered log changes about how a team actually works."
tags: [work, design-docs, leadership, llm]
draft: true
---

The most expensive argument on a fast-moving platform is the one you have twice. Somebody proposes a change, the team thinks hard, a decision lands, everyone moves on. Six months later the same proposal turns up in a review comment, fresh as paint, from someone who wasn't in the room. Now you either relitigate the whole thing from memory, with half the original context missing, or you wave it through and quietly undo a choice that was load-bearing. I've watched both happen. The fix costs about a page.

## Where the memory lives

At work I look after an AI platform that several product teams build against, and it moves at the speed you'd expect of anything with "AI" in the name in 2024. The habit that keeps it coherent is one I've carried since 2018: significant changes get a written design before they get code. Back then it was RFCs into the organisation's knowledge base. On the marketplace I led it was design docs in the repo wiki. On the current platform the habit has compressed into its tightest form yet: a numbered log of architecture decision records, and the closest thing the platform has to a memory.

The numbering is the part people underrate. A pile of design docs is an archive: you go there when you already know what you're looking for. A numbered log is a citation system. "See D12" fits in a review comment, a commit message, or an interruption in a meeting, and it resolves to exactly one document, forever.

## What earns a number

The bar I hold: an ADR records a decision that constrains future decisions. If choosing A over B changes what the next ten changes are allowed to look like, it gets written down. Whether tenants share infrastructure or each get their own. Which system holds the source-of-truth copy of a record. Decisions like those cost almost nothing to make and a fortune to unmake, because within weeks there's code that assumes them.

The other side of the bar matters just as much: if a revert fixes it, it doesn't get a number. A library bump, a renamed module, a tuned timeout. Those live happily in the changelog. Write ADRs for them and you bury the twenty decisions that matter under two hundred that don't, and the log stops being worth reading.

## The form that survives contact

Every entry gets the same skeleton: number, status, date, context, decision, consequences. Alternatives considered, when the argument was close. The whole thing fits on a page, because the real test of an ADR is whether a busy engineer will actually read it when a review comment points at it. If it needs a table of contents, it's a design doc wearing the wrong hat.

Status is the field doing the quiet work. Proposed, accepted, superseded. The rule that makes the log trustworthy is immutability: once accepted, an entry is never edited. Circumstances changed? Write a new entry that supersedes the old one, and mark the old one superseded with a pointer forward. The history of what you believed, and when you stopped believing it, is most of the value.

An invented example, so we have something concrete to point at (no, you don't get the real ones). Say entry twelve reads "D12: one queue per tenant". Context: noisy neighbours were starving each other. Decision: isolation over utilisation. Consequences: more queues to operate, per-tenant backpressure for free. A year on, the tenant count makes that untenable. Nobody touches D12. Someone writes D31, marks D12 superseded, and the log now tells the true story: isolation was right at ten tenants and wrong at a thousand, and we knew what we were trading both times.

## What actually changes

Arguments happen once. When a settled question resurfaces, the answer is a number, and the burden of proof flips: the challenger reads the entry and either brings new context or moves on. New context is genuinely welcome, that's what supersession is for. The tenth identical argument is not.

Onboarding changes shape too. A new engineer can read the whole log in an afternoon and come out knowing why the platform is the shape it is, knowledge that otherwise lives in the heads of whoever was in the room. The log holds something the codebase can't: the code shows the option that won, while the options that lost, and why they lost, carry most of the lessons and appear nowhere else.

Code review gets sharper. "This violates D12" is a different class of comment from "I don't think we do it this way". One is checkable. The other is a vibe with seniority attached.

The deepest effect took me longest to appreciate: the platform stops depending on any one person's memory, mine included. People change teams; people forget. A platform that needs its architect in the room to explain itself has a bus factor of one in the worst possible place.

## The costs, since there are some

The discipline tax is real. An ADR takes an hour you'd rather spend building, at exactly the moment you're keenest to build, and the log only works if the habit holds under deadline pressure. Skipping it "just this once" is how logs die.

Statuses go stale. A decision can quietly stop being true while its entry still says accepted, and a reader a year later takes it at face value. Immutability doesn't excuse you from an occasional audit pass. Superseding is a write somebody has to remember to perform.

And numbering things feels productive, which is a trap. The bikeshed ADR is tempting precisely because it's easy to write, while the queue-topology one is hard. Resist. The bar is constraint on future decisions, and the log's whole value is its density.

## Worth starting even if you're late

Two things to take away. Start the log now, on whatever you have, and backfill entries for the decisions people keep asking about; the payback arrives with the very next argument you don't have twice. And hold the bar hard: numbered, one page, immutable, superseded rather than edited, and only decisions that constrain decisions. Everything else about the practice is negotiable.
