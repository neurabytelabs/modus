import Config

config :modus, Modus.Repo,
  database: System.get_env("DATABASE_PATH") || Path.expand("../priv/data/modus_dev.db", __DIR__)

config :modus, ModusWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "modus_dev_secret_key_base_that_is_at_least_64_bytes_long_for_security_000",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:modus, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:modus, ~w(--watch)]}
  ]

config :modus, ModusWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/modus_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :phoenix_live_view, debug_heex_annotations: true
config :logger, level: :debug
