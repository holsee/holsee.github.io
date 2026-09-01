---
title: "Why Cherry exists"
description: "I used to run my blog on Octopress. Cherry is what I wanted it to become, an old-school static site generator ready for the agentic era."
tags: [personal, elixir, oss, static-site, design-docs]
---

Cherry is the static site generator I wrote in August 2026, in Elixir, and it builds the site you're reading. Its first stable release went out this week, and I've written up why it exists over on its own blog. Here's the short version and the link.

I ran this blog on Octopress for years and loved it the way you love a workshop: plain files, a hacker's toolchain, `rake new_post` and push. It died the way most Octopress blogs died. Touch one theme file and you had silently forked the framework, cut off from every upstream fix. The Ruby toolchain rotted underneath it. And nothing ever checked the output, so a broken link or a missing description reached production, or nobody found it at all.

Cherry is what I wanted Octopress to become, built with four convictions I refused to trade away. A build is a function: same tree in, same bytes out, on every machine, and CI double-builds the fixture sites and fails on a single differing byte. The verifier is the product: `cherry check` builds the whole site in memory, writes nothing, and reports structured diagnostics that name the file to fix. The toolchain is one file: a self-contained executable with the BEAM inside for everyone, a hex package for Elixir folk, and both lanes build byte-identical sites. And customisation never costs you the upgrade path: theme tokens for restyling, ejection that records provenance, and a three-way diff after every upgrade.

Then the part nobody had on the list in 2011. The plain-files, plain-commands shape turns out to be exactly what a coding agent needs, if you finish the thought. Every verb takes `--json`, `cherry schema posts` says what a valid file looks like before an agent writes one, and every build emits `llms.txt` and a markdown mirror of every page. A human and an agent drive the same loop, and Cherry can't tell the difference.

The full post has the reasoning behind each of those, and the failure modes they were designed against: [Why Cherry exists, on cherrybomb.dev](https://cherrybomb.dev/why-cherry-exists/).
