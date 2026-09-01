---
title: "Full Text search in Elixir"
description: "Cherry's built-in search engine is an inverted index in pure Elixir and a 2KB client. Term weighting, plural folding, and a tokenizer that lives in two languages."
tags: [personal, elixir, oss, static-site, algorithms]
---

Set `search: "cherry"` in a Cherry config and the site gets full-text search: a search box, ranked results, a keyboard shortcut. No Node, no npm, no wasm blob, no third-party service. I wrote up how it works on the Cherry blog; this is the summary, because the computer science involved is old, small and genuinely pleasing.

The index is the data structure every search engine from grep to Google grew out of: for each token, the list of documents containing it, with a weight. Building it in Elixir is a fold over the documents, and `Enum.frequencies/1` plus `Map.merge/3` with a resolver do most of the work. A word in a title counts three times, in a tag twice, in prose once, and fenced code blocks are stripped before tokenising so a technical archive's samples don't drown the index in language keywords.

The awkward truth of build-time search is that the index is built in Elixir but the query is typed in a browser. If the two sides tokenise differently, "Algorithms" at build time and "algorithm" at query time never meet. So the tokenizer is deliberately tiny, implemented once in Elixir and once in TypeScript, and a test feeds the same corpus through both and fails if they ever disagree:

```elixir
def tokenize(text) do
  text
  |> String.downcase()
  |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
  |> Enum.filter(&keep?/1)
  |> Enum.map(&fold/1)
  |> Enum.filter(&keep?/1)
end
```

That second `keep?` is load-bearing. Fold the plural of "this" and you get "thi", which isn't a stopword, and suddenly a word carrying zero signal is in every posting list on the site. Every normalisation step can undo a guarantee established earlier, so re-check the invariant after.

Ranking is tf-idf in sixteen lines of TypeScript, in the browser. The postings list length is the document frequency, so idf falls out of data already in hand, and results sort by how many distinct query terms matched before score, which is the difference between search that feels right and search that feels like grep.

Fifty-year-old information retrieval, one Elixir module, one small island. The full walk through the code, the weights and the boring virtues (deterministic, lazy, an enhancement rather than a dependency) is here: [Search without Node, on cherrybomb.dev](https://cherrybomb.dev/search-without-node/).
