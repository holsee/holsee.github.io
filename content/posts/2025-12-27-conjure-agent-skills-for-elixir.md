---
title: "conjure: Agent Skills for Elixir"
description: "A practical guide to Conjure, an Elixir implementation of Anthropic's Agent Skills: loading skills, the progressive-disclosure prompt, and one Session API over four execution backends — local shell, Docker, Anthropic's hosted Skills API, and native Elixir modules."
tags: [personal, elixir, agents, llm]
---

[Conjure](https://github.com/holsee/conjure) is an Elixir library for Anthropic's Agent Skills - following their spec closely providing alternative execution backends. It loads skills off disk, generates the system prompt that lets a model discover them, and runs the tool-use loop — with the same `chat/3` call whether the skill executes as shell commands on your host, inside a Docker container, on Anthropic's hosted Skills API, or as a plain Elixir module in your own BEAM.

It is on Hex as an alpha, under Apache-2.0. This post is the guide I wanted while writing it.

```elixir
def deps do
  [{:conjure, "~> 0.1.1-alpha"}]
end
```

It pulls in `yaml_elixir`, `jason` and `telemetry`, and nothing else. `req` is an optional dependency used only by the S3 and Tigris storage strategies. There is deliberately no HTTP client for the model API itself — more on that below.

## What an Agent Skill is, and why the shape is the point

A skill is a folder with a `SKILL.md` at the top: YAML frontmatter naming and describing it, a markdown body of instructions, and optional resources alongside.

````markdown
---
name: echo
description: |
  A simple echo skill for testing. Use this when asked to echo or repeat messages.
license: MIT
compatibility: python3
allowed-tools: Bash(python3:*) Read
---

# Echo Skill

To echo a message, run:

```bash
python3 scripts/echo.py "Your message here"
```
````

That layout *is* the token economy. A model sees the frontmatter for every skill it has, reads the body of the one it picks, and only loads the resources that skill actually needs. Metadata, then body, then resources — progressive disclosure.

Conjure enforces that split in the struct itself. `Conjure.load/1` walks a directory and parses frontmatter, but leaves `body: nil` and `body_loaded: false`:

```elixir
{:ok, skills} = Conjure.load("priv/skills")

[%Conjure.Skill{
   name: "echo",
   description: "A simple echo skill for testing...",
   path: "priv/skills/echo",
   allowed_tools: "Bash(python3:*) Read",
   body: nil,
   body_loaded: false,
   resources: %{scripts: ["scripts/echo.py"], references: [], assets: [], other: []}
 }] = skills
```

There is `load_all/1` for several directories at once, and `load_skill_file/1` for a packaged `.skill` file, which is just a ZIP of the same layout.

So the system prompt lists only the cheap part — name, description, and where to find the rest:

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

`Conjure.system_prompt(skills)` wraps those in an `<available_skills>` block. The model reads it, decides a skill is relevant, and calls the `view` tool on the location it was given; only then does the body enter the context. A hundred skills cost you a hundred short descriptions, not a hundred full instruction sets.

If you want a body eagerly — to inspect it, to test it — `Conjure.load_body/1` returns the skill with `body` filled and `body_loaded: true`, and `Conjure.read_resource/2` reads one file from inside the skill directory.

## Hello world

Three calls: load, make a session, chat.

```elixir
{:ok, skills} = Conjure.load("priv/skills")

session = Conjure.Session.new_local(skills)

{:ok, response, session} =
  Conjure.Session.chat(session, "Please echo 'Hello from Conjure!'", &api_callback/1)
```

`chat/3` runs the whole tool-use loop: it sends your message with the skills prompt and tool schemas attached, and when the model comes back with `stop_reason: "tool_use"` it executes the tool, feeds the result back, and goes round again until the model stops calling tools. You get the final response plus an updated session, and passing that session into the next `chat/3` continues the conversation.

### you supply the HTTP call

The third argument is the interesting one. Conjure ships no HTTP client and never chooses your model, your auth, or your `Req`-versus-`Finch` religion. It builds the messages and the tool definitions; you make the call.

```elixir
defmodule HelloConjure.Agent do
  @api_url "https://api.anthropic.com/v1/messages"

  defp api_callback(messages) do
    body = %{
      model: "claude-sonnet-4-5-20250929",
      max_tokens: 1024,
      system: system_prompt(),
      messages: messages,
      tools: Conjure.tool_definitions()
    }

    headers = [
      {"x-api-key", api_key()},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    case Req.post(@api_url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response}} -> {:ok, response}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp system_prompt do
    {:ok, skills} = Conjure.load("priv/skills")

    """
    You are a helpful assistant with access to skills.

    #{Conjure.system_prompt(skills)}
    """
  end
end
```

The callback takes the message list and returns `{:ok, response_map}` or `{:error, reason}` — that is the entire contract. It keeps a skills library from dragging an opinion about HTTP into every app that wants one, and it means you can hand it a stub in tests without a network at all. (The repo's `examples/.scripts/` directory does exactly that: a `MockClaudeAPI` module that returns a canned `tool_use` block, so the examples run end to end with no API key.)

`Conjure.tool_definitions/0` returns the four Claude-compatible tool schemas the model is offered: `view`, `bash_tool`, `create_file` and `str_replace`. These are identical across every backend. Only where the bytes actually execute changes.

## Four places a skill can run

### local

The default. Skills execute bash commands directly on the host, which is exactly as unsandboxed as it sounds — the executor logs a loud warning to that effect.

```elixir
session = Conjure.Session.new_local(skills,
  working_directory: skill.path,
  timeout: 30_000,
  max_iterations: 25
)
```

Fine for development and trusted skills you wrote yourself. Not fine for anything a model fetched from the internet.

### docker

The same commands, in a container. Build the sandbox image once:

```bash
mix conjure.docker.build
```

Then use `new_docker/2`, which returns a tuple because it initialises storage and a working directory for you:

```elixir
{:ok, session} = Conjure.Session.new_docker(skills)

{:ok, response, session} = Conjure.Session.chat(session, message, &api_callback/1)

{:ok, _session} = Conjure.Session.cleanup(session)
```

Files the skill creates have to live somewhere your app can reach after the container exits, so Docker sessions take a storage strategy — `Conjure.Storage.Local` by default, with S3 and Tigris also shipped:

```elixir
{:ok, session} =
  Conjure.Session.new_docker(skills,
    storage: {Conjure.Storage.S3, bucket: "my-bucket"},
    on_file_created: fn file_ref, session_id ->
      Logger.info("skill wrote #{file_ref.path} in session #{session_id}")
    end
  )
```

There is a bang variant, `new_docker!/2`, if you would rather it raise. Don't forget `cleanup/1` — it is what tears down the storage the session allocated.

### anthropic's hosted skills

For the document-generation skills (`xlsx`, `pptx`, `docx`, `pdf`), execution happens on Anthropic's side and you never run a container at all. You pass skill *specs* rather than loaded skills:

```elixir
{:ok, session} =
  Conjure.Session.new_anthropic([
    {:anthropic, "xlsx", "latest"},
    {:anthropic, "pdf", "latest"}
  ])

{:ok, response, session} =
  Conjure.Session.chat(session, "Create a budget spreadsheet with monthly expenses", &callback/1)
```

Two things to know. The Skills API needs beta headers, and the library knows which ones:

```elixir
def anthropic_headers do
  [
    {"x-api-key", api_key()},
    {"anthropic-version", "2023-06-01"}
  ] ++ Conjure.API.Anthropic.beta_headers()
end
```

And the session tracks the container id across turns, so a follow-up message lands in the same environment as the first — ask it to add a chart to the spreadsheet it just made and the file is still there. Whatever it created comes back as file references you can pull down:

```elixir
files = Conjure.Session.get_created_files(session)

for %{id: file_id, source: :anthropic} <- files do
  {:ok, content, filename} = Conjure.Files.Anthropic.download(file_id, &files_api_callback/1)
  File.write!(filename, content)
end
```

### native elixir

This is the one that justifies doing any of this in Elixir. A native skill is a module implementing `Conjure.NativeSkill`, executed in-process with full access to your application's runtime — your repos, your caches, your GenServers. No shell, no subprocess, no serialisation.

The behaviour maps the four Claude tools onto four callbacks:

| Claude tool | callback | purpose |
|---|---|---|
| `bash_tool` | `execute/2` | run commands or logic |
| `view` | `read/3` | read resources |
| `create_file` | `write/3` | create resources |
| `str_replace` | `modify/4` | update resources |

Only `__skill_info__/0` is required; implement the callbacks your skill actually needs and declare them in `allowed_tools`, and Conjure generates the tool definitions from that.

```elixir
defmodule MyApp.Skills.CacheManager do
  @behaviour Conjure.NativeSkill

  @impl true
  def __skill_info__ do
    %{
      name: "cache-manager",
      description: "Manage application cache (clear, stats, list keys)",
      allowed_tools: [:execute, :read]
    }
  end

  @impl true
  def execute("clear", _context) do
    Cachex.clear(:my_cache)
    {:ok, "Cache cleared successfully"}
  end

  def execute("stats", _context) do
    {:ok, stats} = Cachex.stats(:my_cache)
    {:ok, inspect(stats, pretty: true)}
  end

  @impl true
  def read("keys", _context, _opts) do
    {:ok, keys} = Cachex.keys(:my_cache)
    {:ok, Enum.join(keys, "\n")}
  end
end
```

```elixir
session = Conjure.Session.new_native([MyApp.Skills.CacheManager])

{:ok, response, session} =
  Conjure.Session.chat(session, "Clear the cache and show me the stats", &api_callback/1)
```

Every callback returns `{:ok, String.t()}` or `{:error, term()}`, because what goes back to the model is text either way. Each also receives a `Conjure.ExecutionContext` carrying the working directory, the allowed paths, the timeout and any executor config you stashed there — which is a reasonable place to hang app-specific data a skill needs.

The win over the local backend is not just speed. It is that the surface a model can reach is a pattern match. `def execute("clear", _ctx)` and `def execute("stats", _ctx)` with no catch-all clause is a whitelist enforced by the compiler, rather than a shell command you are hoping is well-formed.

### picking one at runtime

Because the backends differ only in construction, selecting one is a `case`:

```elixir
def chat(message, backend_type, skills) do
  session =
    case backend_type do
      :local -> Conjure.Session.new_local(skills)
      :docker -> Conjure.Session.new_docker!(skills)
      :anthropic -> Conjure.Session.new_anthropic!(skills)
      :native -> Conjure.Session.new_native(skills)
    end

  Conjure.Session.chat(session, message, &api_callback/1)
end
```

## The pieces underneath

`Session` is a convenience over parts you can use directly when you want a different loop.

```elixir
{:ok, skills} = Conjure.load("priv/skills")

system_prompt = """
You are a helpful assistant.

#{Conjure.system_prompt(skills)}
"""

Conjure.Conversation.run_loop(
  [%{role: "user", content: "Create a Python script"}],
  skills,
  &call_claude(&1, system_prompt, Conjure.tool_definitions()),
  max_iterations: 15
)
```

Below that again there is `Conjure.parse_response/1` to pull tool calls out of a raw response, `Conjure.execute/3` to run a single `ToolCall` against a skill set, and `Conjure.create_context/2` to build the execution context by hand.

For long-lived apps, the registry is a supervised process that owns the loaded skills:

```elixir
children = [
  {Conjure.Registry, name: MyApp.Skills, paths: ["priv/skills"]}
]

# later
skills = Conjure.Registry.list(MyApp.Skills)
pdf = Conjure.Registry.get(MyApp.Skills, "pdf")
:ok = Conjure.Registry.reload(MyApp.Skills)
```

`reload/1` is the one worth knowing about: you can drop a new skill into the directory and pick it up without a restart.

Three mix tasks round it out — `mix conjure.init` scaffolds a skill directory, `mix conjure.validate` checks structure and frontmatter (also available as `Conjure.validate/1`), and `mix conjure.docker.build` builds the sandbox image.

## Rough edges

It is alpha, and I would rather name the sharp bits than have you find them.

The `Conjure.Backend` behaviour — `backend_type/0`, `new_session/2`, `chat/4` — is the right seam, but only the native backend currently routes through it. `Session.chat/3` dispatches `:anthropic` and local/Docker to private functions instead:

```elixir
def chat(%__MODULE__{execution_mode: :anthropic} = session, msg, cb), do: chat_anthropic(session, msg, cb)
def chat(%__MODULE__{execution_mode: :native} = session, msg, cb), do: Backend.Native.chat(session, msg, cb, [])
def chat(%__MODULE__{} = session, msg, cb), do: chat_local(session, msg, cb)
```

The abstraction is real and the behaviour is implemented; the dispatch just has not been cleaned up to go through it uniformly. And the local executor genuinely has no sandboxing, which is documented in an ADR rather than hidden, but is worth saying twice.

The repo carries twenty-two ADRs covering the decisions behind all of the above, and six tutorials that go further than this post does — a log analyser on local skills, document generation on the hosted API, native skills, all four backends in one agent, and a Fly.io deployment with Tigris storage.

## Postscript: it used to be called skillex

I built this over Christmas week as `skillex`, thirty-one commits, and then renamed it. I did the rename the crude way: squashed the whole history into one initial commit rather than carrying it over. Diff the last `skillex` tree against the first `conjure` commit and they are byte-identical apart from a global find-and-replace of the name across the READMEs, the tutorials, two ADRs, a Docker heredoc sentinel and one environment variable.

Except the licence. `skillex` was MIT; `conjure` is Apache-2.0. That is the one substantive change buried in the rename, and it is worth stating out loud rather than leaving for someone to find in a diff. Apache-2.0 carries an explicit patent grant that MIT does not, which matters more for a library about executing model-generated code than for most. If you were depending on `skillex` under MIT, that term changed under you — and a squashed history is a poor way to communicate a licence change. I would carry the real history over next time.

- Repo: [github.com/holsee/conjure](https://github.com/holsee/conjure)
- Docs: [hexdocs.pm/conjure](https://hexdocs.pm/conjure)
