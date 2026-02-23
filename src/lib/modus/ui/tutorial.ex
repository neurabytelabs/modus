defmodule Modus.UI.Tutorial do
  @moduledoc """
  Interactive Tutorial System — ETS-based step tracker for onboarding.

  5 steps guide new users through core MODUS features:
  select_world → inspect_agent → open_chat → try_god_mode → visit_observatory
  """

  @table :modus_tutorial

  @steps [
    %{
      id: :select_world,
      title: "Dünya Seç",
      description: "Bir dünya şablonu seçerek simülasyonunu başlat.",
      target_element: "[data-tutorial='world-select']",
      completion_event: :world_created
    },
    %{
      id: :inspect_agent,
      title: "Agent İncele",
      description: "Bir agent'a tıklayarak detaylarını gör.",
      target_element: "[data-tutorial='agent-card']",
      completion_event: :agent_selected
    },
    %{
      id: :open_chat,
      title: "Sohbet Aç",
      description: "Agent ile sohbet penceresini aç ve konuş.",
      target_element: "[data-tutorial='chat-btn']",
      completion_event: :chat_opened
    },
    %{
      id: :try_god_mode,
      title: "God Mode",
      description: "God Mode ile dünyaya olay enjekte et.",
      target_element: "[data-tutorial='god-mode']",
      completion_event: :god_mode_used
    },
    %{
      id: :visit_observatory,
      title: "Gözlemevi",
      description: "Observatory'de istatistikleri ve grafikleri incele.",
      target_element: "[data-tutorial='observatory']",
      completion_event: :observatory_visited
    }
  ]

  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ets.insert(@table, {:current_step, 0})
    :ets.insert(@table, {:started, false})
    :ets.insert(@table, {:completed, false})
    :ok
  end

  @spec start() :: :ok
  def start do
    ensure_table()
    :ets.insert(@table, {:current_step, 0})
    :ets.insert(@table, {:started, true})
    :ets.insert(@table, {:completed, false})
    :ok
  end

  @spec current_step() :: map() | nil
  def current_step do
    ensure_table()
    idx = get_index()

    if idx < length(@steps) do
      Enum.at(@steps, idx)
    else
      nil
    end
  end

  @spec advance() :: :ok | :completed
  def advance do
    ensure_table()
    idx = get_index() + 1

    if idx >= length(@steps) do
      :ets.insert(@table, {:current_step, idx})
      :ets.insert(@table, {:completed, true})
      :completed
    else
      :ets.insert(@table, {:current_step, idx})
      :ok
    end
  end

  @spec skip() :: :ok
  def skip do
    ensure_table()
    :ets.insert(@table, {:current_step, length(@steps)})
    :ets.insert(@table, {:completed, true})
    :ok
  end

  @spec completed?() :: boolean()
  def completed? do
    ensure_table()

    case :ets.lookup(@table, :completed) do
      [{:completed, val}] -> val
      _ -> false
    end
  end

  @spec reset() :: :ok
  def reset do
    ensure_table()
    :ets.insert(@table, {:current_step, 0})
    :ets.insert(@table, {:started, false})
    :ets.insert(@table, {:completed, false})
    :ok
  end

  @spec steps() :: [map()]
  def steps, do: @steps

  @spec total() :: integer()
  def total, do: length(@steps)

  @spec step_index() :: integer()
  def step_index, do: get_index()

  @spec state() :: map()
  def state do
    ensure_table()
    step = current_step()

    %{
      step: get_index() + 1,
      total: total(),
      title: if(step, do: step.title, else: nil),
      description: if(step, do: step.description, else: nil),
      target_element: if(step, do: step.target_element, else: nil),
      completed: completed?()
    }
  end

  # Private

  defp get_index do
    case :ets.lookup(@table, :current_step) do
      [{:current_step, idx}] -> idx
      _ -> 0
    end
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined, do: init()
  end
end
