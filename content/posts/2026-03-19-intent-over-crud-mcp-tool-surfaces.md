---
title: "Intent over CRUD: designing MCP tool surfaces"
description: "Hand a chat agent a faithful CRUD toolset and it improvises orchestration it shouldn't have to. The design doctrine from shipping an in-app assistant over MCP: shape tools around user intent, hold each server to 4–8 tools, and route servers by role so authorisation is structural."
tags: [work, mcp, agents, llm, api-design, design-docs]
draft: true
---

Hand a very capable model your REST API as a set of tools and watch it flail. Ask "what's on my timetable tomorrow?" and an agent with a faithful CRUD toolset will list calendars, pick one, page through events, filter them in its own context window, and come back eight seconds later with an answer assembled from four tool calls, one of which it fluffed on the first go. Nothing wrong with the model. The tool surface set it up to fail.

For the past six weeks at work I've been building an in-app AI assistant: a chat agent that acts on school data on behalf of the person typing, connected over MCP to a fleet of small servers exposing what the surrounding products can do. I lead the agent and MCP side of it, and the most transferable thing to come out of the work is the design doctrine I wrote down for shaping those servers. The system stays at work; the doctrine travels, so here it is.

## Intent over CRUD

MCP makes the wrong thing very easy, because the wrong thing is a transcription job: take your API, emit a tool per endpoint, ship it. You get something like this (invented for illustration; no real product was harmed):

```text
# a calendar server, transcribed from a REST API
list_calendars   get_calendar   list_events    get_event
create_event     update_event   delete_event
list_attendees   add_attendee   remove_attendee
list_rooms       get_room       list_room_bookings
```

Thirteen tools and climbing, and every user question is now a little orchestration exercise the model has to improvise. Worse, the domain rules live nowhere. When a meeting moves, which fields change? Do the attendees get told? What happens to the room booking? `update_event` answers none of that, so the model reconstructs your business logic from parameter names, live, with a user watching.

Design the same capability around what people ask for and it collapses:

```text
# the same capability, designed around intent
whats_on            day or week, for me or my class
find_free_slot      duration, participants, window
schedule_meeting    title, participants, slot
reschedule_meeting  meeting, new slot
cancel_meeting      meeting, optional reason
```

Five tools. `reschedule_meeting` does the joins, applies the rules, notifies whoever should be notified, and returns one coherent result. Every hop that removes is a round trip through the model you no longer pay for: tokens, latency, and one fewer chance to pick the wrong tool. There's a quieter win too. Tool selection is a matching problem between the user's sentence and your tool descriptions, and a tool named for the user's verb matches the user's sentence.

## Four to eight tools, then split

Every tool definition rides along in every request: name, description, JSON schema, call it 100–200 tokens each. Mount forty tools and that's a few thousand tokens of flat tax on every turn of every conversation, paid before the user types a word. The subtler cost is accuracy. The working rule I wrote down is that routing degrades somewhere past twenty tools in context: the model stops choosing correctly and starts choosing plausibly, which looks fine right up until it doesn't.

So each server gets 4–8 tools, and the ceiling is hard. A server that wants a ninth tool is two servers. Split along the domain seams (scheduling, attendance, admissions), and namespace the tool names so nothing collides across the fleet. Small servers also buy you options later: once each one is narrow and coherent, choosing which servers to mount per session, or eventually per request, becomes the whole selection problem, and it's a far easier one than choosing between forty flat tools.

## Route servers by role

Most products serve several kinds of user with overlapping capabilities, and ours is no exception. The tempting build is one big server with `if role == :teacher` inside every handler. We build per-role variants of each domain server instead, and an agent mounts only its role's set, each server holding to the 4–8 rule.

The pay-off is that authorisation becomes structural. One role's agent doesn't refuse another role's tool; it has never heard of it. There's no branch to get wrong, and nothing for a prompt injection to talk the model into, because the dangerous tool is absent from the list rather than guarded inside a handler. The descriptions get simpler too: no conditional fields, no "only if you're an admin" caveats for the model to misread.

One wee rule that earns its keep: if a tool takes an ID, the same server must carry a search or list tool that produces that ID. An agent must never be expected to know an identifier in advance, because a model that needs an ID it doesn't have will invent one, confidently.

## Keeping it honest

None of this survives contact with real questions unless you measure it, so the doctrine is backed by evals: golden sets of realistic questions per role, scored on whether the agent reached for the right tools. When a server drifts past the ceiling or a description goes vague, the coverage scores say so before a user does. The plumbing underneath is ax_mcp, part of Ax, the Elixir agent framework I've been building since January (open source, coming soon).

## What to steal

- Read your own `tools/list` cold, as the model sees it. If it reads like your database schema, rewrite it around the verbs your users actually say.
- Budget tools the way you budget tokens, because they are tokens: 4–8 per server, split at nine, keep what's mounted under about twenty.
- Make permissions structural. Per-role server variants beat runtime role checks, because the safest tool is the one the model never sees listed.
