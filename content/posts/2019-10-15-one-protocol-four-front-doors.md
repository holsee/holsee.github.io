---
title: "Linking accounts across apps that don't share a login"
description: "Two products, two logins, one person. A user-consented link between accounts lets the apps know they're looking at the same user and pass messages about them, with no shared identity provider. The contract mattered more than the endpoints, and it was proven from four clients."
tags: [work, elixir, ruby, api-design, distributed-systems]
draft: true
---

Apple's Continuity is the thing I keep pointing at when I explain this project. Start an email on your phone and finish it on your Mac; copy on one, paste on the other. The devices don't share a process or a database. They share a trust relationship and a way of talking about the same person, and everything you like about the experience is downstream of that.

We have two products with separate logins that the same person uses. A portfolio built in one should show up in the other, and an action in one should be able to prompt the next step in the other, without either app adopting the other's identity provider to get there. That's the integration service I've built at work this year: "a cross application account association and communication platform", which is the least fun sentence in the repo. The fun ones are the first commit (*Shaken, not stirred*) and the reference app, named after a henchman, because you take your fun where you can. The interesting part isn't the endpoints. It's the shape of the trust, and the document that says what the service will and won't promise.

## a link the user consents to

The link between two accounts is a three-legged handshake, and the design doc doesn't pretend it's novel:

> Just like you would when enabling Google Drive/Dropbox/3rd party application access within an application.

If you've done OAuth from the consuming side, you've done this. App X asks the service to link a user to App Y. The service calls back to Y, and Y sends the user to its own authorisation page, where they log in as themselves, in Y's world, with Y's credentials, and consent. Y confirms to the service; the service mints a secret for the linked pair and hands it to both sides; and from then on every message between the two apps is scoped to that link. Neither app ever sees the other's credentials. The user has said, in both places, "these two accounts are me."

Every identity in play is a self-describing signed token, so the service can tell who is talking without a database lookup: the token carries the app's name and the protocol version that minted it.

## what a link makes possible

Once two accounts are linked, both apps know they're looking at the same person and can act on it. A message from X to Y about that user lands in Y's own account model with no guessing about who it belongs to, which is what the portfolio sync needs. The part I find more interesting is what it opens up: an app can know that a linked user is active on the other side and offer the integration that fits the moment, the way a Mac notices the email you were writing on your phone. Presence and hand-off between web apps that don't share a backend, with the user's explicit consent as the root of trust. Build the link once and every integration after it is a message on an established channel.

## the best part is a document

Before the endpoints, there's a design document, and it's the thing I'd point a junior engineer at. It names the failure mode plainly (an application crashes after acting on a message but before acknowledging it) and then states the guarantee, verbatim:

> `Bond` provides the means by which these communications can be made quickly and reliably, with an at least once delivery guarantee. […] As such, it is highly recommended that messages transmitted are idempotent i.e. do not have any effect if received more than once.

At-least-once, so design your messages to survive being seen twice. And then it's just as clear about what it *won't* give you:

> The order of delivery is not guaranteed, the only guarantee `bond` provides is at least once delivery.

> It is recommended to design the protocol & messages in such a way that the order of operations does not impact the final state. When it comes to state replication etc. this can be achieved through using Conflict Free Replicated Data Types or similar.

And my favourite rule, the one people trip over most:

> System time varies between machines and should not be used as part of the protocol specification. When chronological order / causal relationships are required it is recommended that Logical Clocks are used instead.

It's followed by a reading list of Lamport timestamps, vector clocks, version vectors and matrix clocks. Because the day someone reaches for `System.system_time()` to order events across two machines is the day the integration starts lying, and I would rather that argument be won in a document than in an incident.

The honest tension, which I'll own: the doc documents these as a *contract it mostly delegates*. It builds at-least-once for real, as a pull queue with visibility timeouts on Postgres, which deserves a write-up of its own. It pushes idempotency onto you and tells you why. It offers no ordering at all: that's yours to add with a sequence number if you truly need it. A protocol's most valuable output is often the sentence "we will not do this for you, and here's what to do instead."

## now prove it from four front doors

A protocol that only reads well in the language you wrote it in isn't proven. So the service ships with three other things:

- **An Elixir client**: HTTP abstracted over Tesla so the caller picks their own adapter, and a Plug endpoint that wires up the two inbound callbacks declaratively. Elixir consumers get the protocol as functions.
- **A Ruby client**: 83 lines over Faraday, every method taking an args hash and yielding `(status, body)`. Ruby is what the older products speak, so this is the client they'd actually use.
- **A reference consumer**: a whole worked application that stands on both sides of the handshake, drives the client, and keeps account links as an Ecto state machine (`initiated → authorised → established`). Its tests stub the service's HTTP and assert *both* the records it persisted and the request it sent.

Writing the same protocol four times is the best fuzz-test of an API design there is. The Ruby client is where you find out your JSON shape assumed atoms. The reference app is where you find out the handshake has a leg you under-specified. By the time a real product integrates, the awkward questions have been asked by your own hands, in two languages, against a running service.

## what I'd keep

Make the user the root of trust: a link two accounts have both consented to beats any amount of shared-secret plumbing between backends, and it's the thing that lets apps behave like they know each other. Write the guarantees down before the endpoints, and be as loud about what you won't promise as what you will. And prove the protocol from more than one front door, ideally in a language you'll have to think in. The document is the product; the clients are how you check the document is true.
