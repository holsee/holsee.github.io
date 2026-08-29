---
title: "Entity resolution: the arithmetic of absence"
description: "Entity resolution in about a thousand lines of Go: blocking to keep the comparisons finite, weighted comparators that treat a missing field differently from a wrong one, the arithmetic trap that turns one matching name into a confident merge, and union-find to turn pairs into clusters."
tags: [personal, go, algorithms, data-ontology, semantic-data]
draft: true
---

I have been building a thing that eats CSV files and hands back a graph.
Drop in a few thousand rows about companies from three different places,
and it works out that `ACME HOLDINGS LTD`, `Acme Holdings Limited` and
`acme holdings` are one organisation, glues them into a single canonical
record, and remembers which source each field came from.

That last part is the whole game. Deciding two rows are the same thing is
easy to do badly and interesting to do well, and the interesting bit is
almost entirely about the cases where you should refuse to decide.

## You cannot compare everything

The naive version compares every row with every other row. Ten thousand
rows is fifty million pairs, and that is before anyone uploads a real
file. So you block first: cheap keys that group rows which could
plausibly match, and you only compare within a group.

The blocker I settled on takes the first four characters of the
standardised name plus a country code:

```go
// internal/resolve/block.go
prefix := name
if len(prefix) > 4 {
    prefix = prefix[:4]
}
country := candidateCountryOrNationality(c, ot)
return []BlockKey{BlockKey("nm4:" + prefix + "|cc:" + country)}
```

Four characters is a guess, and it is the honest kind of guess: wide
enough that `Acme Holdings` and `Acme Hldgs` land together, narrow enough
that you are not comparing every British company with every other one.
Blocking trades recall for tractability. Anything the blocker separates
can never match, no matter how good your scoring is, so I would rather
the net was too wide and let the scorer do the filtering.

## Missing is not the same as wrong

Each property in the ontology declares a comparator and a weight, so
matching behaviour is configuration rather than code:

```yaml
# configs/ontology.yaml
- name: name
  comparator: jaro_winkler
  weight: 0.6
- name: country
  comparator: exact
  weight: 0.2
```

Jaro-Winkler for names because it is forgiving about typos and rewards a
shared prefix, exact for country codes because `GB` is either `GB` or it
is not. Then there is a third answer every comparator needs, which took
me longer to appreciate than it should have. If one side has no country
at all, that is not a mismatch. It is silence, and silence should not
count against a pair.

So comparators return `NaN` when either side is empty, and the scorer
drops those from the weighted average:

```go
// internal/resolve/score.go
if math.IsNaN(ps.Score) {
    continue
}
num += ps.Score * w
den += w
```

## The trap hiding in that loop

Look at what happens when almost everything is missing. Two rows both
called `Acme Holdings`, and one of them has nothing else filled in. Name
scores 1.0 at weight 0.6. Country, incorporation date and legal form all
return `NaN` and get skipped, from the numerator and the denominator
alike.

So the total is 0.6 divided by 0.6, which is 1.0. A perfect score. The
arithmetic has quietly turned "the only field we could compare happened
to agree" into "every field we compared agreed unanimously", and with a
threshold of 0.85 those two rows merge.

That is how you end up with one canonical John Smith who is seven
different people.

The fix is to count how much evidence actually fired, and refuse to clear
the threshold on a single comparator:

```go
// internal/resolve/score.go
if nonNaN < s.MinEvidence {
    if floor := threshold - 0.0001; res.Total > floor {
        res.Total = floor
    }
}
res.Decision = res.Total >= threshold
```

Two real comparators minimum. Capping just below the threshold rather
than zeroing the score keeps the number meaningful when a human reads it
later: the pair still ranks above genuinely bad pairs, it just cannot
merge on its own.

With country present on both sides and agreeing, the same pair scores
0.8 over 0.8 and merges properly. With the name at 0.92 and the country
disagreeing, it is 0.552 over 0.8, or 0.69, and it stays apart. Those
numbers feel about right to me, which is worth saying out loud, because
"feels about right" is exactly the sort of judgement that deserves a
golden test pinning it down before it drifts.

## When you actually know, stop guessing

All of that fuzzy machinery is for the case where you have nothing better
than names. When two rows share a legal entity identifier, guessing is
absurd. The scorer short-circuits before any comparator runs:

```go
// internal/resolve/score.go
if va == "" || va != vb {
    continue
}
res.Total = 1.0
res.Decision = true
res.MatchedOn = fmt.Sprintf("id:%s", id.Scheme)
```

Identifier matches are deterministic and they are also the thing an
operator will ask about first, so `MatchedOn` records which scheme did
it. Every merge should be able to answer "why", and "the LEI is the same"
is a better answer than "0.94".

## Pairs are not clusters

Scoring gives you a pile of yes-or-no decisions about pairs. What you
want is groups. That is union-find, path halving and union by rank, and
it is the same fifty lines it has been since the seventies:

```go
// internal/resolve/unionfind.go
func (u *unionFind) find(x int) int {
    for u.parent[x] != x {
        u.parent[x] = u.parent[u.parent[x]]
        x = u.parent[x]
    }
    return x
}
```

There is a real trade-off buried in this step and it is worth being
honest about it. Union-find takes the transitive closure, so if A matches
B and B matches C, then A, B and C are one entity even if A and C were
never compared or were compared and rejected. Chains can drag in things
you would not have merged directly. That is the price of clustering this
way, and the defence is upstream: a threshold strict enough, and an
evidence floor high enough, that the chains stay short.

## Whose value wins

Once a cluster exists, each property needs one canonical value out of
several candidates. The rule that survived contact with real data:
highest-trust source wins, ties break on most recent ingest, and an empty
value never wins at all.

```go
// internal/resolve/value_resolver.go
if isEmptyValue(m.Value) {
    continue
}
if m.Trust > best.Trust {
    best = m
```

A trusted register with a blank field loses to a scruffy CSV that
actually has the answer. Trust ranks the sources you believe, it does not
conjure data out of the ones that stayed quiet.

## What it is all for

The resolution engine sits in the middle of a pipeline with four verbs:
ingest, project, resolve, derive. Rows come in, get projected into
whatever object types the ontology declares, get resolved into canonical
entities, and then typed links are materialised between them, so a
sanctions programme becomes an edge rather than a string sitting in a
column. The result is browsable as a graph, and every canonical field
still points back at the source row it came from.

The sanctions case is the one I have been testing against, because public
sanctions data is genuinely messy in the ways that matter: the same
person transliterated four ways, organisations that share an address but
not a name, identifiers present in some feeds and absent in others. It is
a good adversary for a scorer.

None of the algorithms here are novel. Blocking, Jaro-Winkler, weighted
scoring and union-find are all decades old and thoroughly written up. The
part that took real thought was the arithmetic of absence: deciding what
a missing field means, and noticing that the obvious implementation
answers that question wrongly in a way that looks like confidence.
