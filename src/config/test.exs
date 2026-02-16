import Config

config :modus, Modus.Repo,
  database: Path.expand("../priv/data/modus_test.db", __DIR__),
  pool_size: 5

config :modus, ModusWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "modus_test_secret_key_base_that_is_at_least_64_bytes_long_for_tests_000",
  server: false

config :logger, level: :warning
