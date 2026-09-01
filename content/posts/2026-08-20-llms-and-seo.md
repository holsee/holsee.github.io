---
title: "LLMs and SEO"
description: "Two kinds of readers hit your site now, crawlers and agents. How Cherry serves both from one build, and why doing it in the framework beats doing it in the theme."
tags: [personal, elixir, oss, static-site, agents]
---

A static site used to have one non-human audience: search crawlers. Now it has two. Agents read sites to answer questions, summarise and quote, and they are terrible at reading the HTML your visitors enjoy. Cherry treats both audiences as build outputs, generated from the same content pass as the human pages, so nothing can drift. I've written up the implementation on the Cherry blog; this is the shape of it.

For crawlers, the classic failure is a missing tag rather than a missing technique. Someone writes a lovely theme, forgets the canonical link, and every page competes with itself. So the SEO head (canonical, description, Open Graph, JSON-LD, feed links) is framework-owned HTML handed to the theme as one assign. A theme renders it or fails the contract check; it cannot half-render it. The author writes a `description:` line and the machine does the rest, on every page, forever.

For agents, every content route gets an `index.md` alongside its `index.html`: the same page as markdown, no theme, no navigation. Append `index.md` to any URL on this site and you get exactly the words I wrote. The mirror isn't a converted copy of the HTML and isn't a second pipeline; both are projections of one parsed document in one build pass, so they can't disagree. An `llms.txt` at the root indexes the mirrors so an agent never has to guess the URL structure.

The bit worth stealing is a correctness property enforced by pipeline order. The sitemap and feeds describe the human site, so the mirrors must not leak into them. Rather than filter mirror paths out, Cherry generates the sitemap *before* the mirrors exist. The invariant is free, and no future change to the sitemap code can break it.

The full post has the code for each stage, the emitted head from a real page, and how an `unlisted` CV stays shareable but silent across every surface: [LLMs and SEO, on cherrybomb.dev](https://cherrybomb.dev/llms-and-seo/).
