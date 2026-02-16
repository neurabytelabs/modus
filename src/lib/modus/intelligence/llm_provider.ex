defmodule Modus.Intelligence.LlmProvider do
  @moduledoc """
  LlmProvider — GenServer that abstracts LLM calls across multiple backends.

  Supports:
  - :ollama (local Ollama instance)
  - :antigravity (OpenAI-compatible Antigravity Gateway)

  Stores current config in state. Exposes decide/2, conversation/3, chat/2.
  """
  use GenServer
  require Logger

  alias Modus.Intelligence.{OllamaClient, AntigravityClient}

  # Default config reads from env — prefers Antigravity if configured
  @default_config %{
    provider: :ollama,
    model: "llama3.2:3b-instruct-q4_K_M",
    base_url: "http://modus-llm:11434",
    api_key: nil
  }

  defp init_config do
    antigravity_key = System.get_env("ANTIGRAVITY_API_KEY")
    if antigravity_key && antigravity_key != "" do
      %{
        provider: :antigravity,
        model: System.get_env("ANTIGRAVITY_MODEL") || "gemini-3-flash",
        base_url: System.get_env("ANTIGRAVITY_URL") || "http://host.docker.internal:8045",
        api_key: antigravity_key
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
      antigravity: [
        %{id: "gemini-3-flash", name: "Gemini 3 Flash", local: false},
        %{id: "gemini-3-pro-high", name: "Gemini 3 Pro High", local: false},
        %{id: "claude-sonnet-4-5-thinking", name: "Claude Sonnet 4.5", local: false},
        %{id: "claude-opus-4-6-thinking", name: "Claude Opus 4.6", local: false},
        %{id: "gpt-4.1", name: "GPT-4.1", local: false}
      ]
    }
  end

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, init_config(), name: __MODULE__)
  end

  @doc "Get current LLM config."
  def get_config, do: GenServer.call(__MODULE__, :get_config)

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

  @doc "Chat with a single agent."
  def chat(agent, user_message) do
    GenServer.call(__MODULE__, {:chat, agent, user_message}, 120_000)
  end

  @doc "Test connection to the configured provider."
  def test_connection do
    GenServer.call(__MODULE__, :test_connection, 30_000)
  end

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(config) do
    Logger.info("LlmProvider started: provider=#{config.provider} model=#{config.model} url=#{config.base_url}")
    {:ok, config}
  end

  @impl true
  def handle_call(:get_config, _from, config) do
    {:reply, config, config}
  end

  def handle_call({:set_config, new}, _from, config) do
    merged = Map.merge(config, new)
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
    result = case config.provider do
      :ollama -> OllamaClient.test_connection(config)
      :antigravity -> AntigravityClient.test_connection(config)
      _ -> {:error, "Unknown provider: #{config.provider}"}
    end
    {:reply, result, config}
  end

  # ── Dispatch ────────────────────────────────────────────

  defp dispatch(:decide, [agents, context], %{provider: :ollama} = c) do
    OllamaClient.batch_decide(agents, context, c)
  end

  defp dispatch(:decide, [agents, context], %{provider: :antigravity} = c) do
    AntigravityClient.batch_decide(agents, context, c)
  end

  defp dispatch(:conversation, [a, b, ctx], %{provider: :ollama} = c) do
    OllamaClient.conversation(a, b, ctx, c)
  end

  defp dispatch(:conversation, [a, b, ctx], %{provider: :antigravity} = c) do
    AntigravityClient.conversation(a, b, ctx, c)
  end

  defp dispatch(:chat, [agent, msg], %{provider: :ollama} = c) do
    OllamaClient.chat_with_agent(agent, msg, c)
  end

  defp dispatch(:chat, [agent, msg], %{provider: :antigravity} = c) do
    AntigravityClient.chat_with_agent(agent, msg, c)
  end

  defp dispatch(op, _args, %{provider: p}) do
    Logger.warning("LlmProvider: unknown provider #{p} for #{op}")
    :fallback
  end
end
