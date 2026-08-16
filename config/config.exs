import Config

# Cherry highlights code with MDEx's Lumis engine. This selects the
# right precompiled NIF and must be set before deps compile — keep it.
config :mdex_native, syntax_highlighter: :lumis
