import Config

config :modus,
  ecto_repos: [Modus.Repo]

config :modus, ModusWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ModusWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Modus.PubSub,
  live_view: [signing_salt: "modus_lv_salt"]

config :esbuild,
  version: "0.21.5",
  modus: [
    args: ~w(js/app.js --bundle --target=es2020 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../assets/node_modules", __DIR__)}
  ]

config :tailwind,
  version: "3.4.17",
  modus: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
