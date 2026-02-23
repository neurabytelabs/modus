defmodule Modus.Intelligence.LlmProvider do
  @moduledoc """
  LlmProvider — GenServer that abstracts LLM calls across multiple backends.

  Supports:
  - :ollama (local Ollama instance)
  - :gemini (Google Gemini API — free tier)

  Stores current config in state. Exposes decide/2, conversation/3, chat/2.
  """
  use GenServer
  require Logger

  alias Modus.Intelligence.{OllamaClient, GeminiClient}

  defp init_config do
    gemini_key = System.get_env("GEMINI_API_KEY")

    if gemini_key && gemini_key != "" do
      %{
        provider: :gemini,
        model: System.get_env("GEMINI_MODEL") || "gemini-2.0-flash",
        base_url: "https://generativelanguage.googleapis.com/v1beta",
        api_key: gemini_key
      }
    else
      %{
        provider: :ollama,
        model: System.get_env("OLLAMA_MODEL") || "llama3.2:3b-instruct-q4_K_M",
        base_url: System.get_env("OLLAMA_URL") || "http://modus-llm:11434",
        api_key: nil
      }
    end
  end

  @doc "Available models for each provider (shown in UI)."
  def available_models do
    %{
      ollama: [
        %{id: "llama3.2:3b-instruct-q4_K_M", name: "Llama 3.2 3B (Q4)", local: true}
      ],
      gemini: [
        %{id: "gemini-2.0-flash", name: "Gemini 2.0 Flash (Free)", local: false},
        %{id: "gemini-2.0-flash-lite", name: "Gemini 2.0 Flash Lite (Free)", local: false}
      ]
    }
  end

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, init_config(), name: __MODULE__)
  end

  @doc "Get current LLM config. Uses persistent_term for non-blocking reads."
  def get_config do
    try do
      :persistent_term.get(:llm_config)
    rescue
      ArgumentError -> GenServer.call(__MODULE__, :get_config)
    end
  end

  @doc "Update LLM config. Keys: :provider, :model, :base_url, :api_key"
  def set_config(new_config) when is_map(new_config) do
    GenServer.call(__MODULE__, {:set_config, new_config})
  end

  @doc "Batch decide actions for agents."
  def decide(agents, context) do
    GenServer.call(__MODULE__, {:decide, agents, context}, 120_000)
  end

  @doc "Generate conversation between two agents."
  def conversation(agent_a, agent_b, context) do
    GenServer.call(__MODULE__, {:conversation, agent_a, agent_b, context}, 120_000)
  end

  @doc "Chat with a single agent. Bypasses GenServer to avoid blocking on batch_decide."
  def chat(agent, user_message) do
    config = get_config()

    case config.provider do
      :ollama -> OllamaClient.chat_with_agent(agent, user_message, config)
      :gemini -> GeminiClient.chat_with_agent(agent, user_message, config)
      _ -> :fallback
    end
  end

  @doc "Test connection to the configured provider."
  def test_connection do
    GenServer.call(__MODULE__, :test_connection, 30_000)
  end

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(config) do
    Logger.info(
      "LlmProvider started: provider=#{config.provider} model=#{config.model} url=#{config.base_url}"
    )

    :persistent_term.put(:llm_config, config)
    GeminiClient.reset_circuit_breaker()
    {:ok, config}
  end

  @impl true
  def handle_call(:get_config, _from, config) do
    {:reply, config, config}
  end

  def handle_call({:set_config, new}, _from, config) do
    merged = Map.merge(config, new)
    :persistent_term.put(:llm_config, merged)
    Logger.info("LlmProvider config updated: provider=#{merged.provider} model=#{merged.model}")
    {:reply, :ok, merged}
  end

  def handle_call({:decide, agents, context}, _from, config) do
    result = dispatch(:decide, [agents, context], config)
    {:reply, result, config}
  end

  def handle_call({:conversation, a, b, ctx}, _from, config) do
    result = dispatch(:conversation, [a, b, ctx], config)
    {:reply, result, config}
  end

  def handle_call({:chat, agent, msg}, _from, config) do
    result = dispatch(:chat, [agent, msg], config)
    {:reply, result, config}
  end

  def handle_call(:test_connection, _from, config) do
    result =
      case config.provider do
        :ollama -> OllamaClient.test_connection(config)
        :gemini -> GeminiClient.test_connection(config)
        _ -> {:error, "Unknown provider: #{config.provider}"}
      end

    {:reply, result, config}
  end

  # ── Dispatch ────────────────────────────────────────────

  defp dispatch(:decide, [agents, context], %{provider: :ollama} = c) do
    OllamaClient.batch_decide(agents, context, c)
  end

  defp dispatch(:decide, [agents, context], %{provider: :gemini} = c) do
    GeminiClient.batch_decide(agents, context, c)
  end

  defp dispatch(:conversation, [a, b, ctx], %{provider: :ollama} = c) do
    OllamaClient.conversation(a, b, ctx, c)
  end

  defp dispatch(:conversation, [a, b, ctx], %{provider: :gemini} = c) do
    GeminiClient.conversation(a, b, ctx, c)
  end

  defp dispatch(:chat, [agent, msg], %{provider: :ollama} = c) do
    OllamaClient.chat_with_agent(agent, msg, c)
  end

  defp dispatch(:chat, [agent, msg], %{provider: :gemini} = c) do
    GeminiClient.chat_with_agent(agent, msg, c)
  end

  defp dispatch(op, _args, %{provider: p}) do
    Logger.warning("LlmProvider: unknown provider #{p} for #{op}")
    :fallback
  end

  # Catch-all for unexpected messages
  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
