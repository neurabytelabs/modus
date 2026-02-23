defmodule Modus.UI.NotificationCenter do
  @moduledoc """
  Notification Center — stores categorized notifications with read/unread state.

  Categories: :world, :agent, :economy, :system
  Priority: :info, :warning, :critical
  Max 100 notifications (ring buffer via list trimming).
  """

  @table :modus_notifications
  @max_notifications 100

  @doc "Initialize ETS table."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ets.insert(@table, {:notifications, []})
    :ets.insert(@table, {:counter, 0})
    :ok
  end

  @doc "Add a notification."
  @spec add(atom(), atom(), String.t()) :: :ok
  def add(category, priority, message)
      when category in [:world, :agent, :economy, :system] and
             priority in [:info, :warning, :critical] do
    counter = :ets.update_counter(@table, :counter, {2, 1})

    notification = %{
      id: counter,
      category: category,
      priority: priority,
      message: message,
      read: false,
      timestamp: DateTime.utc_now()
    }

    [{:notifications, existing}] = :ets.lookup(@table, :notifications)
    updated = [notification | existing] |> Enum.take(@max_notifications)
    :ets.insert(@table, {:notifications, updated})
    :ok
  end

  @doc "List notifications. Pass :all or a category atom."
  @spec list(atom()) :: [map()]
  def list(filter \\ :all) do
    [{:notifications, notifications}] = :ets.lookup(@table, :notifications)

    case filter do
      :all -> notifications
      category -> Enum.filter(notifications, &(&1.category == category))
    end
  end

  @doc "Count unread notifications."
  @spec unread_count() :: integer()
  def unread_count do
    list(:all) |> Enum.count(&(not &1.read))
  end

  @doc "Mark a specific notification as read."
  @spec mark_read(integer()) :: :ok
  def mark_read(id) do
    [{:notifications, notifications}] = :ets.lookup(@table, :notifications)

    updated =
      Enum.map(notifications, fn
        %{id: ^id} = n -> %{n | read: true}
        n -> n
      end)

    :ets.insert(@table, {:notifications, updated})
    :ok
  end

  @doc "Mark all notifications as read."
  @spec mark_all_read() :: :ok
  def mark_all_read do
    [{:notifications, notifications}] = :ets.lookup(@table, :notifications)
    updated = Enum.map(notifications, &%{&1 | read: true})
    :ets.insert(@table, {:notifications, updated})
    :ok
  end

  @doc "Clear all notifications."
  @spec clear() :: :ok
  def clear do
    :ets.insert(@table, {:notifications, []})
    :ok
  end

  # ── Milestone Detection ──────────────────────────────────

  @doc "Detect milestone from an event and add notification."
  @spec detect_milestone(map()) :: :ok
  def detect_milestone(%{type: :birth, data: data}) do
    name = data[:name] || "Someone"
    add(:agent, :info, "👶 #{name} bir çocuğu oldu!")
  end

  def detect_milestone(%{type: :death, data: data}) do
    name = data[:name] || "Someone"
    add(:agent, :warning, "💀 #{name} öldü...")
  end

  def detect_milestone(%{type: :build, data: data}) do
    name = data[:builder] || data[:name] || "Someone"
    add(:world, :info, "🏠 #{name} bir yapı inşa etti!")
  end

  def detect_milestone(%{type: :friendship_formed, data: data}) do
    name = data[:name] || "Someone"
    add(:agent, :info, "🤝 #{name} yeni bir arkadaş buldu!")
  end

  def detect_milestone(%{type: :skill_mastered, data: data}) do
    name = data[:name] || "Someone"
    skill = data[:skill] || "a skill"
    add(:agent, :info, "🎓 #{name} #{skill} ustası oldu!")
  end

  def detect_milestone(%{type: :goal_completed, data: data}) do
    name = data[:name] || "Someone"
    add(:agent, :info, "🎯 #{name} hedefine ulaştı!")
  end

  def detect_milestone(_event), do: :ok
end
