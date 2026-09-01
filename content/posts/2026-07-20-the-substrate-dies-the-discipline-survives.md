---
title: "Control planes in agent SDLCs"
description: "Three days ago my agentic-SDLC spec had a control plane: a CAS store, leases, signed-commit authority, a reconciler. Today it has GitHub issues. It's the best deletion I've made this year, and the reasoning travels to any team putting agents in the delivery loop."
tags: [personal, agents, asdlc, design-docs]
---

Three days ago the spec had a control plane. A store with compare-and-swap transactions. Leases on claimable artefacts. Authority as signed commits. A level-triggered reconciler. It was thorough, it resolved twenty defects a logical audit had found in the first draft, and it was wrong. Today the control plane is gone and GitHub issues do the job. This is the write-up of the deletion.

## What the spec is for

An agentic software development lifecycle is a multi-stage, multi-agent workflow that mimics how software delivery actually works and is executed by agents end to end. Raw requests go in one end; reviewed, tested, documented, merged changes come out the other. The specification is the thing every agent, skill and tool defers to; none of them restate its rules.

The one sentence that matters is this: GitHub is the shared memory. Issues and pull requests hold the work in flight, the repository holds durable truth, and any agent or human can pick up the work from the record alone, without replaying the conversation that produced it. If you can't resume from the record, you don't have a lifecycle, you have a chat log.

## The first two drafts, and the twenty defects

The first draft was the full specification. A logical audit of it the same day turned up twenty defects, and the second draft resolved them by building machinery: a control-plane/code-plane split, a single write path through a store with compare-and-swap transactions, authority as signed commits, a reconciler with leases. A couple of revisions later it had grown a practice layer (skills, templates, agent roles, gitflow, Conventional Commits, Keep a Changelog) and had its interfaces tidied after a cold-read dry run.

Every one of those changes was right in isolation. Together they'd built a small database and a scheduler to solve problems GitHub already solves.

## Four rounds of grilling

The third draft came out of four rounds of owner-led grilling. The question in each round was the same: what does this mechanism give us that the platform doesn't? Most of the answers were "nothing, if you let the platform do it":

- Identity. The store minted ids transactionally so they'd be unique and race-free. GitHub issue numbers are already unique, atomic and race-free by construction. So a work item's id is its issue number with a one-letter prefix for its type, numbers interleave across types, and nobody needs them to be dense.
- System of record. Issues and pull requests hold what's happening; the repository holds what's true. Triage and review passes are structured, append-only comments on the thing they describe. A board is a label query. A stored view can drift; a query can't.
- Authority. Signed commits proved who did what. Account identity does that already: agents run as a bot account that cannot approve or merge, so every human decision is a comment, review or merge provably made by a human, and artefacts cite the URL.
- Gates. Per-stage transaction guards became one hard gate at merge: branch protection, required checks, required human review. Stage transitions are labels moved by skill discipline; anything mislabelled gets caught at the gate that matters.
- Scheduling. The reconciler became one coding-agent session per work item. Concurrency is parallel sessions on parallel items, and git push plus the GitHub API serialise everything shared.

Deleted: the store and its CAS engine, the leases, the reconciler, the authority manifest, and the requirement that ids be dense. Kept: the stages, both flow definitions, code review in parallel with security review, the full findings ledger (now in the work item's own contract file), Gherkin acceptance criteria with same-branch coverage, gitflow, Conventional Commits, Keep a Changelog, and every agent role.

The substrate dies. The discipline survives.

## What's left is thin on purpose

The practice layer retargeted to the GitHub-native record in a day: a small set of agent roles (triage, analysis, product, development, code review, security review, QA, technical writing), skills that bundle their own templates so agents instantiate structure rather than invent it, git hooks, a definition-of-done lint, and a thin wrapper over the GitHub CLI. The spec governs itself, too: it carries a semantic version, every work item records the version it was minted under and completes under it, and changes to the spec flow through the pipeline as maintenance patches like anything else.

One more honesty note. The changelog records which agent typed each revision, and most rows name a model. I was the one grilling. That's the division of labour I want: the high-value engineering is architecture, invariants and standards, setting the constraints within which agents can cook. Build the factories that build the cars, and architect to protect what matters.

## If you're doing this

Before you build a control plane for agents, list what your platform already guarantees. Identity, ordering, authority and audit are all things GitHub gives you for free if you stop fighting it. Keep the discipline (stages, gates, append-only history, one session per item) and let the platform be the substrate. And write the deletion into the changelog with the same care as the addition; the deletion is the more useful record.
