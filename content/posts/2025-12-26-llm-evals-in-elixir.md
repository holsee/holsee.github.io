---
title: "deep_eval_ex: LLM-as-judge metrics for Elixir"
description: "A port of DeepEval's metrics to the BEAM: how a relevancy score becomes three LLM calls and some arithmetic, how a few hundred cases judge concurrently, and why the whole test suite mocks the judge."
tags: [personal, elixir, evals, llm]
---

I've been writing more agent code lately, and I wanted to evaluate it the way I evaluate everything else: inside `mix test`, with a number, and a reason when the number moves. Python has [DeepEval](https://github.com/confident-ai/deepeval) from Confident AI, whose LLM-as-judge metrics are well designed and Apache-licensed, so I spent a couple of evenings porting them across: [deep_eval_ex](https://github.com/holsee/deep_eval_ex). The prompts are the valuable part and they aren't mine, so the attribution is spelled out in the README, the NOTICE and a header on every ported file. This post is about the one idea that makes "evaluate an LLM" tractable: you use an LLM to do it, carefully.

## A score is not a string comparison

The naive way to score "is this answer relevant to the question" is to eyeball it. The DeepEval way, which I ported straight across, is to make the model do the eyeballing in steps you can inspect. AnswerRelevancy is three LLM calls, not one:

```elixir
# lib/deep_eval_ex/metrics/answer_relevancy.ex
def do_measure(test_case, opts) do
  with {:ok, statements} <- generate_statements(actual_output, opts),
       {:ok, verdicts}   <- generate_verdicts(input, statements, opts),
       score = calculate_score(verdicts),
       {:ok, reason} <- maybe_generate_reason(score, input, verdicts, include_reason, opts) do
    {:ok, Result.new(metric: metric_name(), score: score, ...)}
  end
end
```

First call: break the answer into atomic statements. Second call: for each statement, is it relevant to the question: yes, no, or "idk". Third call: write a one-line reason for the score. The score itself is then plain arithmetic, no model involved:

```elixir
defp calculate_score([]), do: 1.0
defp calculate_score(verdicts) do
  relevant = Enum.count(verdicts, fn %{verdict: v} -> v != :no end)
  relevant / length(verdicts)
end
```

That structure is the whole trick. Instead of asking a model for a number and trusting it, you ask it for a decomposition and a set of small classifications, and you compute the number yourself from those. The intermediate statements and verdicts come back in the result's metadata, so when a score looks wrong you can read exactly which statement the judge marked irrelevant and argue with it. An opaque 0.6 is useless; "these two of five statements were judged off-topic, here they are" is a bug report.

Every judge call goes out with a JSON schema and OpenAI's strict structured-output mode, so a verdict is constrained to `["yes", "no", "idk"]` at the API level rather than parsed hopefully out of prose. Anything the model still manages to say that isn't one of those normalises to `:no`: fail safe, not fail relevant.

## Metrics behind one behaviour

There are seven metrics (exact match, G-Eval, faithfulness, hallucination, answer relevancy, contextual precision and recall), and they share a `BaseMetric` behaviour whose `__using__` macro wraps every `measure/2` with validation and `:telemetry` spans, so a metric author writes only the interesting `do_measure/2` and gets timing, error events and a latency field for free. G-Eval is the odd one out and the most powerful: you hand it a plain-English criterion and it generates its own evaluation steps before scoring, which is the "define a rubric in a sentence" pattern the G-Eval paper is about.

The assertions plug straight into ExUnit, which is where I actually want them:

```elixir
use DeepEvalEx.ExUnit
assert_passes(test_case, DeepEvalEx.Metrics.Faithfulness, threshold: 0.8)
```

## Evals are embarrassingly parallel

Every metric ends in a network call to a judge, so an eval suite is a pile of independent, IO-bound work — precisely the shape the BEAM is good at. `evaluate_batch/3` takes the fan-out as an argument:

```elixir
results = DeepEvalEx.evaluate_batch(test_cases, [Metrics.ExactMatch], concurrency: 20)
```

Twenty judge calls in flight instead of twenty in a row, each parked on a scheduler rather than holding a thread, and the wall clock set by the concurrency limit rather than the number of cases. That matters more than it sounds: AnswerRelevancy is three sequential calls per case, so a few hundred cases is a four-figure pile of round trips, and doing them one after another is the difference between a coffee and an afternoon. Because the assertions are ExUnit tests, `async: true` gets the same treatment across the suite.

## The judge is a stub in the tests

Here's the bit I'd defend hardest, because it's the thing that makes an eval library testable at all. Every metric ends in an LLM call, and you cannot put a real API call in a test suite: it's slow, it costs money, and it isn't deterministic, which is precisely the property a test needs. So there's a `Mock` adapter backed by an ETS table that matches on the prompt text and returns a canned structured response:

```elixir
Mock.set_schema_response(~r/breakdown and generate a list of statements/i,
  %{"statements" => ["The laptop has a Retina display.", "It has a 12-hour battery life."]})
Mock.set_schema_response(~r/determine whether each statement is relevant/i,
  %{"verdicts" => [%{"verdict" => "yes"}, %{"verdict" => "yes"}]})

assert {:ok, result} = AnswerRelevancy.measure(test_case, adapter: :mock)
```

The tests never assert on a model's judgement; they assert on the arithmetic and the plumbing given a known judgement. That's the right seam. The framework's job is to turn a decomposition into a score reproducibly; whether the model decomposes well is the model's problem, tested against real prompts, not something a CI run should depend on. The whole point of computing the score from verdicts rather than asking for it directly is that this seam exists to test against.

It's on hex at 0.1.0, seven metrics, and it does what I needed: it lets me put a number on agent output inside `mix test`, hundreds of cases at a time, and read why when the number moves.

## Where to look

- Repo: https://github.com/holsee/deep_eval_ex; hex package `deep_eval_ex`.
- Ported from Confident AI's DeepEval (Apache-2.0).
