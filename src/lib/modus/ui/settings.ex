defmodule Modus.UI.Settings do
  @moduledoc """
  Settings Panel — ETS-based user preferences with categories.

  Categories: general, display, llm, controls
  """

  @table :modus_settings

  @defaults %{
    # General
    language: "TR",
    theme: "dark",
    # Display
    show_names: true,
    show_needs_bars: true,
    # LLM
    provider: "ollama",
    model: "llama3.2:3b-instruct-q4_K_M",
    fallback: true,
    # Controls
    keyboard_shortcuts: true
  }

  @categories %{
    general: [:language, :theme],
    display: [:show_names, :show_needs_bars],
    llm: [:provider, :model, :fallback],
    controls: [:keyboard_shortcuts]
  }

  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    Enum.each(@defaults, fn {k, v} ->
      :ets.insert(@table, {k, v})
    end)

    :ok
  end

  @spec get(atom()) :: any()
  def get(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, val}] -> val
      _ -> Map.get(@defaults, key)
    end
  end

  @spec get(atom(), any()) :: any()
  def get(key, default) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, val}] -> val
      _ -> default
    end
  end

  @spec set(atom(), any()) :: :ok
  def set(key, value) when is_atom(key) do
    ensure_table()
    :ets.insert(@table, {key, value})
    :ok
  end

  @spec all() :: map()
  def all do
    ensure_table()

    @defaults
    |> Map.keys()
    |> Enum.into(%{}, fn k -> {k, get(k)} end)
  end

  @spec reset() :: :ok
  def reset do
    ensure_table()

    Enum.each(@defaults, fn {k, v} ->
      :ets.insert(@table, {k, v})
    end)

    :ok
  end

  @spec category(atom()) :: map()
  def category(cat) when is_atom(cat) do
    ensure_table()
    keys = Map.get(@categories, cat, [])
    Enum.into(keys, %{}, fn k -> {k, get(k)} end)
  end

  @spec categories() :: map()
  def categories, do: @categories

  @spec defaults() :: map()
  def defaults, do: @defaults

  defp ensure_table do
    if :ets.whereis(@table) == :undefined, do: init()
  end
end
