---
title: "Growing a test language"
description: "Guy Steele gave the best talk on language design I know using only words of one syllable, defining the longer ones as he went. The trick he was demonstrating is the one I later borrowed for a test framework, and it's still the only design that ages well."
tags: [personal, api-design, design-docs]
draft: true
---

In 1998 Guy Steele stood up at OOPSLA and gave a keynote in which he let himself use only words of one syllable. Any word with more, he had to define first, out of the words he already had. So before he could say "machine" he had to build it from small words, and before he could talk about the thing he was there to talk about, he had to grow the words to talk about it with. By the end he was discussing type systems and generics fluently, in a vocabulary he had assembled in front of the audience in under an hour. The talk is called *Growing a Language*, and the form is the argument.

::video{youtube="_ahvzDzKdB0" title="Guy Steele, Growing a Language, OOPSLA 1998"}

The argument is that you can't design a big language up front and get it right, and a small language that can't grow stays small for ever. What works is a small core plus a way for its users to add words that look and feel like the ones that came in the box. Plan for growth, and the plan is the language.

That talk, along with my other adventures in Lisp, has been quietly inspirational at points throughout my career. In one instance I helped develop a text-based testing framework for automation, and used the very principles from the talk to turn it from a fragile, repetitive framework into a powerful, composable tool for the QA engineers embedded in our engineering teams: a small core of primitives, and the freedom for a tester to define a new word from the words that already existed, so the test language grew in the hands of the people writing the tests rather than in a backlog against the framework. The scenarios ended up reading like the sentences people said in planning, because that's who had defined the words.

Go and watch the talk. It might be one of, if not the, greatest talks of all time, delivered on a good old projector.

## Where to look

- Guy Steele, *Growing a Language*, OOPSLA 1998 keynote: https://www.youtube.com/watch?v=_ahvzDzKdB0
- The written version: *Higher-Order and Symbolic Computation* 12, 221–236 (1999).
