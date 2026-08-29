---
title: "Per-tenant vocabulary with gettext domains"
description: "The same product calls a School a University for one customer and an Institution for another. That is translation within a single language, so I pointed the i18n toolchain at it: gettext domains as customer vocabularies, with pluralisation, interpolation and tooling thrown in for free."
tags: [work, elixir, otp, api-design]
draft: true
---

The products I work on sell to schools, universities and exam boards, and those worlds do not share a dictionary. One customer's "School" is another's "University" and a third's "Institution". Same screen, same feature, and still the words are wrong for somebody. Nobody wants a system that calls their university a school.

I had a think about what this problem actually is, and the answer surprised me: it is translation. English to English, admittedly, but structurally identical to i18n, the same message rendered in different words depending on who is reading. And Elixir already ships an industrial-grade toolchain for exactly that shape of problem. So I wrote terminator, a small OTP library that points gettext at it. (The name was irresistible. It terminates terms.)

## the pun that does the work

Gettext gives you two axes, and most applications only ever use one. The famous axis is the locale: `en`, `fr`, and friends. The quieter one is the domain, normally used to split translations into namespaces like "errors" or "emails". A translation lives at the intersection of the two: locale picks the directory, domain picks the file, `priv/gettext/<locale>/LC_MESSAGES/<domain>.po`.

Terminator's whole trick is to keep the locale axis meaning language and re-point the domain axis at the customer. One gettext domain per customer vocabulary, and a term's "translation" into that vocabulary is an ordinary `.po` entry:

```po
# priv/gettext/en/LC_MESSAGES/ib.po
msgid "awarding body"
msgstr "organisation"

msgid "identity"
msgstr "user"

msgid "reference"
msgstr "IB school code"
```

The `msgid` is the neutral term the codebase speaks; the `msgstr` is what this vocabulary calls it. Better still, the default vocabulary costs nothing to maintain, because gettext hands back the msgid whenever a translation is empty. Leave every `msgstr` blank and a customer on the neutral vocabulary sees the neutral words. That fallback normally papers over missing translations; here it is load-bearing.

Resolution is one delegation deep: `Terminator.getterm(domain, term)` lands on `Gettext.dgettext(Terminator.Gettext, domain, term)` and that is the whole lookup.

```elixir
# README.md
domain = "ib"
Terminator.getterm(domain, "identity")
#=> "user"

Terminator.put_locale("fr")

Terminator.getterm(domain, "identity")
#=> "utilisateur"
```

That second half is the payoff for keeping the axes orthogonal. Vocabulary and language compose: a French-speaking user of a customer whose dialect says "user" gets "utilisateur", straight out of `fr/LC_MESSAGES/ib.po`, and neither concern knows the other exists. Gettext's locale is per-process, which suits a request cycle nicely: set it once from the session and every lookup downstream is in the right language and the right dialect.

## keeping the extractor fed

There is one snag. `mix gettext.extract` builds the `.pot` template files by spotting gettext calls at compile time, and it can only see literal arguments. Terminator's lookups are dynamic by design (domain and term arrive at runtime), so as far as the extractor is concerned the library contains no messages at all, and the tooling that makes gettext pleasant to live with goes blind.

The fix is a compile-time shim: generate a clause for every known domain and term pair whose only job is to hold a literal `dgettext_noop` call still while the extractor photographs it.

```elixir
# lib/terminator/backend/gettext.ex
  @terms ["reference", "identity", "awarding body"]
  @domains ["feg", "ib"]
  # ...
  for domain <- @domains, term <- @terms do
    @doc false
    def noop(unquote(domain), unquote(term)) do
      dgettext_noop(unquote(domain), unquote(term))
      :noop
    end
  end
```

`dgettext_noop` translates nothing; it exists purely to mark a message for extraction. With those clauses compiled in, the standard workflow survives untouched: `mix gettext.extract` writes a `.pot` per vocabulary, `mix gettext.merge` fans it out to each locale, and onboarding a customer vocabulary becomes "add a domain, fill in a `.po` file". Those files are plain, diff-able text that translation tools have understood for a couple of decades, which matters here, because terminology is exactly the kind of thing a product person should be able to review in a merge request.

And since `:gettext` sits in the project's compilers list, the `.po` files compile into function clauses on the backend module. A term lookup at runtime is a pattern match, with no file parsing or caching layer in sight. (The repo has a wee helper that dumps the compiled module's abstract code, because I wanted to see those generated clauses with my own eyes. I recommend the exercise; it demystifies gettext completely.)

## the edges

Two things to know before you lift this. Gettext falls back to the msgid, never across locales: an empty `msgstr` in a French `.po` means a French speaker on the neutral vocabulary gets the English term, so going properly multilingual means filling in locales × vocabularies worth of files. That multiplication is the real price of the pun. And terminator is a prototype: the term list and the domain map live in module attributes for now, where configuration should be. The backend sitting behind each domain is already swappable though, so a database-backed resolver could replace gettext for one tenant without the call sites noticing.

## take the trick, not the library

None of this is Elixir-specific. If your product speaks one language to many audiences, you have an i18n problem wearing a fake moustache, and nearly every stack ships gettext or something shaped like it. Keep locale meaning language, spend the domain axis on the audience, make your msgids the neutral terms so the empty-string fallback works for you, and add whatever no-op shim your extractor needs to keep the tooling in play. In exchange you get pluralisation, interpolation, per-process language switching and mature editor support, for a problem that never mentioned i18n once.
