[
  name: "violet-field",
  version: "0.1.0",
  description: "holsee's theme: violet field, amber signal, monospace rail.",
  cherry_contract: "1.0",
  templates: [
    layout: [
      assigns: [:site, :inner, :page_title, :head_extra, :nav, :search, :page_class],
      doc: "Outer HTML shell wrapped around every rendered page."
    ],
    page: [
      assigns: [:site, :doc],
      doc: "A freeform page from the pages collection."
    ],
    post: [
      assigns: [:site, :doc],
      doc: "A single blog post with title, date, and tags."
    ],
    post_list: [
      assigns: [:site, :posts],
      doc: "Reverse-chronological index of published posts."
    ],
    tag: [
      assigns: [:site, :tag, :posts, :story_href],
      doc: "Published posts carrying one tag; links to the tag's story when one exists."
    ],
    portfolio_timeline: [
      assigns: [:site, :portfolio],
      doc: "The developer story: profile header, dated timeline, open source."
    ],
    story: [
      assigns: [:site, :tag, :portfolio, :posts],
      doc: "One tag across the whole story: portfolio entries plus blog posts."
    ],
    cv: [
      assigns: [:site, :cv],
      doc: "The employer-shaped CV: linear, dense, print-first."
    ],
    not_found: [
      assigns: [:site],
      doc: "The 404 page."
    ]
  ],
  # The token manifest is the theme's public styling API. Defaults are the
  # The token manifest is the theme's public styling API. Defaults are the
  # dark rendition — this site is dark by design; `[data-theme="light"]`
  # redefines every colour token for the opt-in light rendition.
  tokens: [
    "--color-bg": [default: "#150e1f", doc: "Page ground: the violet field."],
    "--color-surface": [default: "#1d1430", doc: "Raised ground: inline code, panels, search drawer."],
    "--color-well": [default: "#100a18", doc: "Sunken ground: code blocks, video letterbox."],
    "--color-fg": [default: "#ece6f5", doc: "Body text."],
    "--color-muted": [default: "#a698c0", doc: "Secondary text, tinted from the ground's hue."],
    "--color-border": [default: "#2f2247", doc: "Hairline rules and control borders."],
    "--color-accent": [default: "#f0b354", doc: "The warm signal: links and anything actionable."],
    "--color-accent-strong": [default: "#ffd08f", doc: "Hover/active accent."],
    "--color-mark": [default: "#b98cff", doc: "Structural violet: tags, markers, rules, focus."],
    "--color-selection": [default: "#3d2b63", doc: "Text selection ground."],
    "--syn-keyword": [default: "#ff9ecb", doc: "Syntax: keywords."],
    "--syn-string": [default: "#9ee6c8", doc: "Syntax: strings and characters."],
    "--syn-comment": [default: "#8878a8", doc: "Syntax: comments (italic)."],
    "--syn-function": [default: "#f0b354", doc: "Syntax: functions and methods."],
    "--syn-constant": [default: "#c9a4ff", doc: "Syntax: constants, numbers, booleans."],
    "--syn-type": [default: "#7fd4e8", doc: "Syntax: types, modules, tags, attributes."],
    "--syn-variable": [default: "#ece6f5", doc: "Syntax: variables and default code text."],
    "--syn-punct": [default: "#a698c0", doc: "Syntax: punctuation and operators."],
    "--font-display": [
      default: "\"Bricolage Grotesque\", ui-sans-serif, system-ui, sans-serif",
      doc: "Display face for headings and titles (self-hosted variable woff2)."
    ],
    "--font-prose": [
      default: "\"Literata\", Charter, Georgia, serif",
      doc: "Long-form reading face (self-hosted variable woff2)."
    ],
    "--font-mono": [
      default: "\"JetBrains Mono\", ui-monospace, \"SF Mono\", Consolas, monospace",
      doc: "Code and the metadata rail: dates, tags, years."
    ],
    "--measure": [default: "39rem", doc: "Reading column width (~70ch)."],
    "--wrap": [default: "52rem", doc: "Outer column; media may use its full width."]
  ]
]
