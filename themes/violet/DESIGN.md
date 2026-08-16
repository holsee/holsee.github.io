# violet-field — design system

holsee's own theme, written for this archive. Brief-pinned by the author:
unique dark, purple, interesting typography, good monospace for code.

## World

- **Purple is the field, not the accent.** The ground is violet-black
  (`--color-bg: #150e1f`), surfaces are violet (`--color-surface`), code sits
  in a deeper violet well (`--color-well`), and even secondary text is tinted
  from that hue (`--color-muted: #a698c0`) rather than grey. This is the
  decision that separates the theme from the near-black-plus-neon-accent dark
  theme every tool ships.
- **Amber is the only warm colour, and it means "you can act on this."**
  `--color-accent: #f0b354` is links and nothing else. Violet
  (`--color-mark`) carries structure: tags, list markers, year rules, focus
  rings, table headings.
- **Dark is not a preference here.** There is no `prefers-color-scheme`
  override: the site is dark for everyone, and light
  (`:root[data-theme="light"]`) is a real second rendition reached only by the
  toggle. The scene is an engineer reading in the evening, between an editor
  and a browser.

## Faces

Three self-hosted variable woff2 files (~188KB total, latin), in
`assets/fonts/`. No external font CDN at runtime.

- **Display — Bricolage Grotesque** (`--font-display`): headings, post titles,
  register entries, the wordmark. Chosen for character; ink traps and slightly
  condensed forms keep long titles from going limp at 3rem.
- **Prose — Literata** (`--font-prose`): body text at 1.0625rem/1.75. Built for
  long reading, which is what 35 archived posts demand.
- **Mono — JetBrains Mono** (`--font-mono`): code, and the metadata rail —
  dates, tags, years, nav, footer. Monospace here is data and measurement,
  never costume.

## Structure

- **The measure holds text; media breaks out.** `--measure: 39rem` (~70ch)
  centred inside `--wrap: 52rem`. Prose, headings and lists stay at the
  measure; `pre`, `.video-embed`, tables, figures and image-only paragraphs
  take the full column, because on this site the conference photo and the
  process graph are the evidence.
- **The register.** The blog index groups entries by year behind a violet
  `.year-rule`, with ISO dates in tabular monospace against Bricolage titles.
  Thirty-five posts read as a body of work rather than a feed.
- **Video.** `.video-embed` gets `aspect-ratio: 16/9` with an absolutely
  positioned iframe. The migration emitted this wrapper and no theme styled
  it, so every video on the site rendered at the iframe default of 304×154.
  Audio embeds (Mixcloud, SoundCloud) keep their provider's height instead.

## Verified

Contrast on the built pages: dark 7.06:1 body, 7.41:1 links, 15.95:1 code;
light 6.71:1 body. Both renditions exceed the 4.5:1 floor. No horizontal
overflow at 390px or 1280px. `cherry check --strict` clean at 140 pages.

## Notes for later

`themes/violet` is a site-local theme, so its directory name must differ from
the manifest `name:` until the upstream Cherry fix ships — see
`Cherry.Theme.Resolver.site_local?/2`.
