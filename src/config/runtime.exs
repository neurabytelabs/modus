import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "missing SECRET_KEY_BASE env variable"

  config :modus, ModusWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: secret_key_base

  config :modus, Modus.Repo,
    database: System.get_env("DATABASE_PATH") || "/app/priv/data/modus.db"
end

# Ollama config (all environments)
config :modus, Modus.Intelligence.OllamaClient,
  url: System.get_env("OLLAMA_URL") || "http://localhost:11434",
  model: System.get_env("OLLAMA_MODEL") || "llama3.2:3b-instruct-q4_K_M",
  timeout: String.to_integer(System.get_env("OLLAMA_TIMEOUT") || "90000")

# Gemini API config (Google AI — free tier)
config :modus, Modus.Intelligence.GeminiClient,
  api_key: System.get_env("GEMINI_API_KEY") || "",
  default_model: System.get_env("GEMINI_MODEL") || "gemini-2.0-flash"
