---
title: "conjure: Agent Skills for Elixir"
description: "An Elixir take on Anthropic's Agent Skills: progressive disclosure, one Session API over four backends. Then I squashed the whole thing and republished it under a new name and a different licence."
tags: [personal, elixir, agents, llm]
draft: true
---

Over the past week I built an Elixir library for Anthropic's Agent Skills, twice. First as `skillex`, thirty-one commits across Christmas week; then, yesterday, I squashed the lot and republished it as [conjure](https://github.com/holsee/conjure). The interesting engineering is the progressive-disclosure model and a single session API over four very different execution backends. The interesting confession is what the rename actually changed, which is almost nothing, and one thing that matters.

## What an Agent Skill is, and why the shape is the point

An Agent Skill is a folder with a `SKILL.md` at the top: YAML frontmatter naming and describing the skill, a markdown body of instructions, and optional resources alongside. The layout *is* the token economy. A model sees the frontmatter for every skill it has, reads the body of the one it picks, and only loads the resources that skill actually needs. Metadata, then body, then resources. Progressive disclosure.

So the system prompt the library generates lists only the cheap part (name, description, and where to find the rest):

```elixir
# lib/conjure/prompt.ex
def format_skill(%Skill{} = skill) do
  """
  <skill>
  <name>#{skill.name}</name>
  <description>#{escape_xml(skill.description)}</description>
  <location>#{Skill.skill_md_path(skill)}</location>
  </skill>
  """
end
```

The model reads that, decides a skill is relevant, and uses a `view` tool to read the `SKILL.md` at the given location; only then does the body enter the context. A hundred skills cost you a hundred short descriptions, not a hundred full instruction sets. That's the entire reason the format exists, and getting it right is most of what the library is for.

## One session, four places a skill can run

The part I'm happiest with is that "run this skill" means the same thing whether the code runs on your laptop, in a container, on Anthropic's hosted Skills API, or as a native Elixir module. One call:

```elixir
{:ok, response, session} =
  Conjure.Session.chat(session, "Create a script that calculates fibonacci", &api_callback/1)
```

Behind it is a `Backend` behaviour (`backend_type/0`, `new_session/2`, `chat/4`) with four implementations. Local runs `bash` on the host (with a loud "NO SANDBOXING" warning in the logs). Docker runs the same commands in a container for untrusted skills. Anthropic hands execution to the hosted API for its document-generation skills. Native dispatches to a type-safe Elixir module implementing a `NativeSkill` behaviour, no shell at all. The tool schemas the model sees (`view`, `bash`, `create_file`, `str_replace`) are identical across all four; only where the bytes actually execute changes.

And the library ships no HTTP client. This was a deliberate ADR: you pass in an API callback, and the library never chooses your model, your auth or your `Req`-versus-`Finch` religion. It builds the messages and the tools; you make the call. That keeps a skills library from dragging an opinion about HTTP into every app that wants one.

(I'll be honest about a rough edge, because the post is about honesty: three of those four backends are wired through `Session.chat/3` directly, and only the native one currently routes through the `Backend` behaviour I just described. The abstraction is real and the seam is right; the dispatch hasn't been cleaned up to go through it uniformly yet. Alpha means alpha.)

## The rename, and the one thing it changed

`skillex` was thirty-one commits and it worked. Then I renamed it to `conjure`, and I did it the crude way: squashed the entire history into a single initial commit rather than carrying it over. If you diff the last `skillex` tree against the first `conjure` commit, they are byte-identical apart from a global find-and-replace of the name, in the READMEs, the tutorials, the two architecture-decision records, a Docker heredoc sentinel and one environment variable. All the interesting content (the Session API, the backends, ADR-0019 on the unified execution model, ADR-0020 on the backend behaviour) carried across unchanged.

Except the licence. `skillex` was MIT. `conjure` is Apache-2.0. That's the one substantive change buried in the rename, and it's the one worth stating out loud rather than leaving for someone to discover in a diff. Apache-2.0 carries an explicit patent grant that MIT doesn't, which is the sort of thing that matters more for a library about executing model-generated code than for most. If you were depending on `skillex` under MIT, that term changed under you when it became `conjure`, and a squashed history is a poor way to communicate a licence change. I'd do the carry-over with real history next time.

`conjure` is on hex as an alpha. It does the progressive-disclosure loop, it runs skills in four places behind one interface, and it made me think harder than I expected about how much a rename can quietly change.

## Where to look

- Repo: https://github.com/holsee/conjure; hex package `conjure` (alpha).
