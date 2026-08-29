---
title: "Prompts as migrations, conversations as processes"
description: "Two months into building an LLM gateway in Elixir with no framework to lean on: prompt templates versioned like migrations, a GenServer per conversation, a self-hosted embedding model as a supervised child, and one seam across two providers."
tags: [work, elixir, otp, llm, api-design]
draft: true
---

The quickest way to get GPT-4 into a product is about ten lines in a controller. Concatenate a string, POST it to OpenAI, render whatever comes back. It works in the demo. Then a second team does it, and a third, and the organisation has prompt fragments and retry logic smeared across every codebase, with nobody able to say what was sent to which model or what it cost.

For the past two months I've been building the alternative at work: an Elixir service that owns the model calls and gives our product teams an HTTP API for operations like rephrase, summarise and translate. It's been a solo build near enough, and there's no LangChain for Elixir to lean on, so the patterns got worked out first-hand. Four of them feel settled enough to write down, and three of the four are really about what the BEAM gives you for free.

## version prompts like migrations

A prompt changes for reasons that have nothing to do with logic: a model deprecation, a tone complaint, a better example. Old callers may depend on the old behaviour, and when a change goes wrong you want a diff and a way back. That's the lifecycle of a schema migration, so prompts get a migration's treatment: files on disk, one directory per operation, one subdirectory per version, with a JSON schema beside them to keep the shape honest. Illustratively:

```json
// priv/prompts/summarise/0.2/prompt.json
{
  "meta": {"name": "summarise", "version": 0.2},
  "model": {"name": "gpt-4", "temperature": 0.0},
  "system_prompt": "Summarise the text you are given in at most three sentences. ...",
  "user_prompt": {
    "template": "${text}",
    "parameters": {"text": "The text to summarise."}
  }
}
```

Everything the call needs is in the file: model, sampling options, system prompt, and a user prompt template with `${param}` placeholders. The loader scans the template for parameters and, in strict mode, refuses a call that passes an argument the template doesn't declare or misses one it does. Adding an operation is adding a directory; there's no code change and no deploy of anything except data. Changing one is adding `0.3` beside `0.2`, never editing in place. Callers pin a version or take the latest, and "latest" is nothing grander than `Enum.max` over the directory names. Prompt changes go through merge-request review, same as everything else that matters.

## a conversation is a process

HTTP is stateless and a chat is not, and everywhere else that mismatch means a session store: Redis, a table, a cache with a TTL, and a job to sweep it. On the BEAM the natural home for conversation state is a process. A GenServer is a process with state and a mailbox, and starting one costs a few microseconds and a few kilobytes, so each conversation gets its own, holding its message history. It's registered by reference in a Registry (the runtime's process phone book) and started on demand under a DynamicSupervisor (a supervisor whose children come and go at runtime). The tree, in shape:

```elixir
# illustrative
children = [
  {DynamicSupervisor, strategy: :one_for_one, name: Conversations.Supervisor},
  {Registry, keys: :unique, name: Conversations.Registry},
  {Nx.Serving, serving: Embeddings.serving(), name: Embeddings, batch_size: 8, batch_timeout: 100}
]
```

The reference works like a session id: the same ref reaches the same process, and callers never see a pid. Idle conversations shut themselves down on a timer after a couple of minutes, so there's no reaper job to write. Every message is also written to Postgres for audit, which leaves a recovery path open: if the process dies, the ref is the key for reloading the chat log into a fresh one. A pile of lifecycle machinery you'd otherwise build out of infrastructure collapses into supervisor decisions.

## retrieval without an embeddings API

The last child in that list is the one I'd defend hardest. The embedding model runs inside the service as a supervised child of the application, instead of behind someone else's API. Bumblebee pulls a sentence-transformer model from Hugging Face, Axon compiles it through EXLA, and `Nx.Serving` turns it into a batching inference server (batches of eight, a 100 ms window) that any process in the tree can call like a function.

The documents we'd want to search over are other people's, and shipping them to a third party just to turn them into vectors is a decision I'd rather not make on their behalf. Self-hosting means the text never leaves the service, and the marginal cost of an embedding is zero, which changes how freely you can use retrieval. The vectors go into a FAISS index wrapped in a GenServer, with a small in-memory store mapping ids back to source chunks. A search embeds the query, takes the k nearest neighbours, and maps the labels back to text to hand the model as context. A few hundred dimensions, a flat index, nothing clever. Retrieval-augmented generation sounds grand; it's a few dozen lines of Elixir once the model is a process you can call.

## two providers, one seam

The service speaks to OpenAI and to Azure OpenAI, and which one is configuration the caller never sees. They're nearly the same API, with differences exactly annoying enough to justify the seam. Auth, for a start:

```elixir
def headers(:azure, api_key),
  do: [{"Content-Type", "application/json"}, {"api-key", api_key}]

def headers(:openai, api_key),
  do: [{"Content-Type", "application/json"}, {"Authorization", "Bearer " <> api_key}]
```

Azure also routes each model through its own deployment with its own URL, spells the model names differently (`gpt-35-turbo`, no dot), and streams extra events (content-filter results, role-only chunks) that the stream buffer has to skip. So the seam is mostly mapping tables: request models to deployment URLs on the way out, Azure model names back to OpenAI spellings on the way in, and callers only ever learn one vocabulary. When a requested model isn't available on a provider, the seam is also where the policy lives: fall back to a smaller model with a warning in the log, or fail the request. Which is right depends on the operation (a degraded rephrase beats an error; a degraded rubric might not), which is why it's a logged, visible decision rather than a silent one.

Token counting rides the same seam: tiktoken bindings count every prompt against a per-model price sheet before it goes out, so "what does this feature cost" is a query rather than a surprise on the invoice.

## what you can take from it

Build the seam before the second team calls the vendor directly. An operation called `summarise` is a promise you can keep for years; the model, provider and prompt behind it become data changes, invisible to callers.

Version prompts like migrations from day one. They'll change more often than the code around them, for worse reasons, and a diff plus a way back earns its keep within the first month.

And if your runtime gives you cheap supervised processes, use them for what they're for. A conversation is a process and cleanup is a timer; even the embedding model is just another child in the tree. The BEAM predates all of this by decades and turns out to be quietly excellent at it.
