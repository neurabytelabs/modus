defmodule Modus.UI.SmartToast do
  @moduledoc """
  Smart Toast — priority-based toast notification queue.

  Levels: :info (grey, 3s), :warning (amber, 5s), :critical (red, persistent)
  Max 3 visible, FIFO queue.
  """

  @table :modus_toasts
  @max_visible 3

  @doc "Initialize ETS table."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ets.insert(@table, {:queue, []})
    :ets.insert(@table, {:counter, 0})
    :ok
  end

  @doc "Show a toast. Returns the toast map."
  @spec show(atom(), String.t(), map()) :: map()
  def show(level, message, opts \\ %{}) when level in [:info, :warning, :critical] do
    counter = :ets.update_counter(@table, :counter, {2, 1})

    duration =
      case level do
        :info -> 3000
        :warning -> 5000
        :critical -> nil
      end

    toast = %{
      id: counter,
      level: level,
      message: message,
      duration: duration,
      timestamp: DateTime.utc_now(),
      extra: opts
    }

    [{:queue, existing}] = :ets.lookup(@table, :queue)
    updated = existing ++ [toast]
    :ets.insert(@table, {:queue, updated})
    toast
  end

  @doc "Dismiss a toast by id."
  @spec dismiss(integer()) :: :ok
  def dismiss(id) do
    [{:queue, existing}] = :ets.lookup(@table, :queue)
    updated = Enum.reject(existing, &(&1.id == id))
    :ets.insert(@table, {:queue, updated})
    :ok
  end

  @doc "Get visible toasts (max 3)."
  @spec queue() :: [map()]
  def queue do
    [{:queue, existing}] = :ets.lookup(@table, :queue)
    Enum.take(existing, @max_visible)
  end

  @doc "Reset all toasts."
  @spec reset() :: :ok
  def reset do
    :ets.insert(@table, {:queue, []})
    :ok
  end
end
