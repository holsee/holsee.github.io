---
title: "Cola: a lock beat three CRDTs for collaborative forms"
description: "Several people filling in one HTML form at once. I built four prototypes to find the right model (three flavours of CRDT and one that refuses them), and the OTP one is the one I'd ship."
tags: [work, elixir, otp, liveview, crdt, bake-off]
draft: true
---

The feature is easy to describe and awkward to build: several people open the same HTML form at once, fill it in together, and see each other's edits as they happen. Not a shared document. A form: fields, controls, validation, a definition the server owns. I spent a research spike building four prototypes of it, side by side, in one Phoenix umbrella. Three of them lean on CRDTs. The fourth, the one I'd actually ship, refuses them on purpose, and it's called Cola. This is the write-up. I'll keep the product and the customer out of it and just call the prototype by its codename, cola.

## Why a form is not a document

Almost everything written about collaborative editing is about text, and almost all the tooling is CRDT-shaped: every client holds a replica, edits merge without coordination, the server is a relay. That is a superb model for a shared paragraph. It is not obviously the right model for a form, where the server has to validate the result, and where two people typing into the same date field at the same time is a bug, not a merge.

So rather than argue, I built five routes into one test-bed and made them all answer the same question:

| Route | Approach | Authority |
|---|---|---|
| `/cola` | Plain HTML form over Phoenix Channels | **Server** (OTP) |
| `/control` | Custom control on an Automerge delta-CRDT | Browser (dumb relay) |
| `/ytext` | Plain and rich text on YJS CRDTs | Browser (Node server) |
| `/editor` | CKEditor's commercial collaboration | CKEditor's cloud |
| `/counter` | A LiveView spike | Server |

Two axes fall out of that table, and they're the real finding. Top to bottom, authority moves from the server to the browser to somebody else's servers. And the two CRDT libraries split on licensing: YJS open source, CKEditor a 30-day commercial trial round-tripping your data through `cke-cs.com`. The README's own annotations, "(Open Source)" against one row and "(Commercial ~ Data through CKEditor cloud servers)" against another, are the closest thing to a conclusion I wrote down at the time. For a form full of somebody's personal details, where your data goes is not a footnote.

## Cola: the server keeps authority

Cola is the one I designed from scratch and the one I'd build on. It starts from the opposite premise to a CRDT: the client does not own a document, it owns a *view* of the server's state.

The form definition is parsed with Floki, and the server builds authoritative state from it: a process per form, a process per element, a process per joined user, each in its own registry. A process on the BEAM is a few kilobytes with its own mailbox, so one per form field is the natural unit rather than an extravagance, and a Registry is the runtime's phone book for finding them by name. A user joins, selects a control, edits it, leaves. Every change is broadcast to everyone joined.

The interesting part is what happens when two people reach for the same field, and it's where the anti-CRDT stance earns its keep. Each element process is a GenServer (a process with state that handles its messages one at a time, which is what makes it a lock without a mutex), holding one field, `selected_by`, and the entire mutual-exclusion rule is three clauses that pattern-match on it:

```elixir
# apps/cola/lib/cola/element.ex
def handle_call({:select, user_ref}, _from, state = %{selected_by: nil}) do
  notify_state_change(state.form_ref, {:element_selected, state.id, user_ref})
  {:reply, :ok, %{state | selected_by: user_ref}}
end

def handle_call({:select, user_ref}, _from, state = %{selected_by: user_ref}) do
  {:reply, :ok, state}   # already mine, no-op
end

def handle_call({:select, user_ref}, _from, state = %{selected_by: other}) do
  {:reply, {:error, "Already selected by #{other}"}, state}
end
```

Free, mine, or someone else's: that's the whole algorithm, and there isn't a single `if` in it. The middle clause is the neat one: binding `selected_by: user_ref` in *both* the message and the state matches only when the same user re-selects what they already hold. A write is guarded the same way (`update_value` only succeeds `when user_ref == owner`), so the lock is enforced on read *and* write by the shape of the function heads.

This is precisely the thing a CRDT exists to avoid, and I put it in deliberately. On a form, two people editing the same field is a UX problem long before it's a merge problem. They can't both fill in the same date. One of them should see the other is there, and wait. A lock is just telling the truth about that, where a CRDT would silently merge two answers into one wrong one.

The cost of a lock is that it's state you must release when a browser tab dies, and this is the other half of why it belongs on the BEAM. A user session is a process with a 60-second expiry, and when it stops, its `terminate/2` deselects everything it held. `terminate/2` is the callback the runtime invokes as a process shuts down, so release-on-exit is a place to put code rather than a mechanism to build. The runtime makes per-user lifetime something you can observe and act on, which is exactly what a lock needs and exactly what a stateless relay can't give you.

## The CRDT routes, and the thing they get for free

The `/control` route is the mirror image: the server is deliberately dumb. It's a Phoenix Channel that relays Automerge changes and keeps the last snapshot in a one-slot ETS table so a late joiner can catch up. All the convergence happens in the browser. Two designs, same repo, same fortnight, pointed in opposite directions: that contrast *is* the experiment.

And Automerge handed me something Cola makes me work for. One of my seven goals was "maintain an audit trail of changes", and in the OTP design that's an unticked box with a `# TODO Add to audit log the action` next to it. In Automerge it's a one-liner, because the CRDT already keeps the whole change history:

```javascript
const auditLog = (model) =>
  Automerge.getHistory(model).map(s => [s.change.message, s.snapshot.listItems.length])
```

That's the honest case *for* CRDTs, sitting in the same repo as the case against, and I'd rather have both in front of me than a strong opinion.

`/counter` is the odd one out: a tiny LiveView, added the same week LiveView first appeared in public. It has a button wired to an event with no handler, so clicking it crashes the view and you watch it remount, supervised, in milliseconds. I wanted to feel what server-rendered collaboration was like before betting a feature on it. Too early to bet in early 2019. Not too early to have in the room.

## What I'd actually ship, and what's still WIP

Cola, and it isn't close. A form is structured, server-validated, personal data, and every one of those words argues for the server keeping authority. CRDTs are the right tool when the merge genuinely is the feature (shared prose) and the wrong one when "merge" is a euphemism for "pick one of two conflicting answers and hope".

I'll be honest about how far the spike got: `/cola`'s browser client is still write-only. It reports selections and edits to the server and the server broadcasts them back, but the inbound handler currently just logs them to the console instead of applying them to the DOM. The template says as much, in bold. The engine is real and tested; the last mile of wiring it back into the page is the WIP. That's the true state of a research spike, and the method is what I'd keep regardless: four approaches in one test-bed, the same question asked of each, and the trade-offs written down where I can find them again. I've run every bake-off since the same way.
