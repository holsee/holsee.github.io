---
title: "What building 0.2.0 taught us"
description: "Styling as a ladder, light and dark as one value, components that survive theme swaps, and the HEEx spike with its real numbers."
tags: [personal, elixir, oss, static-site, bake-off]
draft: true
---

Cherry 0.2.0 was the templates and styling release, the two places where static site generators traditionally make you choose between someone else's taste and a fork. I've written up what building it taught me on the Cherry blog. Four lessons, in short.

Styling wanted to be a ladder. The old menu was two items, override nothing or own everything, so I kept asking "what is the smallest amount of ownership that solves this?" and the answers arranged themselves into rungs: a token (`cherry config tokens.--color-accent "#7c3aed"` and the whole theme follows), a stylesheet that loads last and wins by cascade layers rather than specificity fights, one overlaid template, ownership with a provenance receipt, and finally your own theme. Every "how do I change X" support question is really "which rung is X on".

`light-dark()` deleted a third of the CSS problem. Both official themes used to carry three synchronised copies of every colour decision. Now each token is one pair, `light-dark(#c0134f, #ff4d7d)`, and the theme toggle flips a single `color-scheme` property. When the platform grows a primitive that models your exact problem, delete your workaround with prejudice, and add a CI test so nobody reintroduces it.

Components had to belong to the framework, not the theme, or swapping themes would break your content. Figures, video facades and callouts are directives expanded before markdown and styled by whatever theme is active.

And the HEEx spike, with numbers. EEx or HEEx had been the oldest open question in the design doc, so rather than decide by taste I measured: the full HEEx pipeline runs inside a packed release at about half a millisecond per template, for which you get escaping by default and compile-checked markup. The answer to "EEx or HEEx" became a file extension. Spikes with numbers end arguments that taste never will.

The full post, including the mobile tap-target sweep that found the nav links two pixels short of the WCAG floor: [What building 0.2.0 taught us, on cherrybomb.dev](https://cherrybomb.dev/what-building-0-2-0-taught-us/).
