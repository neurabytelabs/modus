defmodule Modus.Mind.DreamEngine do
  @moduledoc """
  GenServer that manages agent dreams.

  Dreams are generated from affect-weighted episodic memories using LLM narratives.
  Dream type is determined by conatus level, dominant affect, and social bonds:
  - Low conatus (<0.3) + high sadness → nightmare
  - High joy → pleasant dream
  - Strong social relationships → social dream
  """

  use GenServer

  alias Modus.Mind.{EpisodicMemory, AffectMemory, DreamPromptBuilder}
  alias Modus.Intelligence.LlmProvider

  @table :agent_dreams
  @max_dreams_per_agent 20

  defmodule Dream do
    @moduledoc "A single dream record for an agent."
    @type dream_type :: :pleasant | :nightmare | :social

    @type t :: %__MODULE__{
            agent_id: String.t(),
            dream_text: String.t(),
            dream_affect: atom(),
            dream_type: dream_type(),
            timestamp: DateTime.t()
          }

    defstruct [:agent_id, :dream_text, :dream_affect, :dream_type, :timestamp]
  end

  # --- Public API ---

  @doc "Start the DreamEngine GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generate a dream for the given agent.

  Uses episodic memories, affect state, and social context to produce
  a surreal dream narrative via the LLM provider.
  """
  @spec dream(map()) :: {:ok, Dream.t()} | {:error, term()}
  def dream(agent) do
    GenServer.call(__MODULE__, {:dream, agent}, 30_000)
  end

  @doc "Retrieve stored dreams for an agent."
  @spec get_dreams(String.t(), keyword()) :: [Dream.t()]
  def get_dreams(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    init_table()

    :ets.lookup(@table, agent_id)
    |> Enum.map(fn {_, dream} -> dream end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc "Determine dream type from agent state."
  @spec classify_dream_type(map()) :: Dream.dream_type()
  def classify_dream_type(agent) do
    conatus = Map.get(agent, :conatus_energy, 0.5)
    affect = Map.get(agent, :affect, :neutral)
    social_bonds = Map.get(agent, :social_bonds, [])

    cond do
      conatus < 0.3 and affect == :sadness -> :nightmare
      affect == :joy -> :pleasant
      length(social_bonds) >= 2 -> :social
      conatus < 0.3 -> :nightmare
      true -> :pleasant
    end
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    init_table()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:dream, agent}, _from, state) do
    result = generate_dream(agent)
    {:reply, result, state}
  end

  # --- Private ---

  defp init_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:bag, :public, :named_table, read_concurrency: true])
    end
  end

  defp generate_dream(agent) do
    agent_id = Map.get(agent, :id, "unknown")
    dream_type = classify_dream_type(agent)

    memories = EpisodicMemory.recall(agent_id, limit: 5)
    affect_memories = AffectMemory.recall(agent_id, limit: 5)

    prompt = DreamPromptBuilder.build(agent, memories, affect_memories, dream_type)

    dream_text =
      try do
        case LlmProvider.chat(agent, prompt) do
          {:ok, text} -> text
          _ -> fallback_dream(dream_type, agent_id)
        end
      rescue
        _ -> fallback_dream(dream_type, agent_id)
      end

    dream = %Dream{
      agent_id: agent_id,
      dream_text: dream_text,
      dream_affect: Map.get(agent, :affect, :neutral),
      dream_type: dream_type,
      timestamp: DateTime.utc_now()
    }

    store_dream(dream)
    {:ok, dream}
  end

  defp store_dream(dream) do
    init_table()
    :ets.insert(@table, {dream.agent_id, dream})

    all = :ets.lookup(@table, dream.agent_id)

    if length(all) > @max_dreams_per_agent do
      sorted = all |> Enum.sort_by(fn {_, d} -> d.timestamp end, {:asc, DateTime})
      to_remove = Enum.take(sorted, length(all) - @max_dreams_per_agent)

      for {_, d} <- to_remove do
        :ets.match_delete(@table, {dream.agent_id, d})
      end
    end
  end

  defp fallback_dream(:nightmare, agent_id) do
    "#{agent_id} wanders through dissolving corridors, hunger gnawing at fading edges of existence."
  end

  defp fallback_dream(:social, agent_id) do
    "#{agent_id} sits in a circle of familiar faces that shift and merge, voices echoing shared memories."
  end

  defp fallback_dream(:pleasant, agent_id) do
    "#{agent_id} drifts through golden meadows where every blade of grass hums with quiet contentment."
  end
end
