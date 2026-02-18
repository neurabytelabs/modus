defmodule Modus.Protocol.SecretKeeping do
  @moduledoc """
  Secret keeping — trust-based information sharing.
  Agents can hold secrets and only share them with trusted friends.
  Secrets have a trust threshold that must be met for sharing.
  """

  @table :agent_secrets
  @max_secrets 10
  @default_trust_threshold 0.6

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc "Store a secret for an agent."
  @spec store_secret(String.t(), String.t(), keyword()) :: map()
  def store_secret(agent_id, content, opts \\ []) do
    init()
    trust_threshold = Keyword.get(opts, :trust_threshold, @default_trust_threshold)
    category = Keyword.get(opts, :category, :personal)

    secret = %{
      id: "sec_#{:erlang.unique_integer([:positive])}",
      content: content,
      category: category,
      trust_threshold: ensure_float(trust_threshold),
      shared_with: [],
      created_at: System.system_time(:second)
    }

    existing = get_secrets(agent_id)
    updated = Enum.take([secret | existing], @max_secrets)
    :ets.insert(@table, {agent_id, updated})
    secret
  end

  @doc "Attempt to share a secret with another agent based on trust."
  @spec try_share(String.t(), String.t(), String.t(), float()) ::
          {:ok, map()} | {:denied, :insufficient_trust}
  def try_share(owner_id, target_id, secret_id, trust_level) do
    init()
    secrets = get_secrets(owner_id)

    case Enum.find(secrets, &(&1.id == secret_id)) do
      nil ->
        {:denied, :not_found}

      secret ->
        if ensure_float(trust_level) >= ensure_float(secret.trust_threshold) do
          # Mark as shared
          updated_secret = %{secret | shared_with: Enum.uniq([target_id | secret.shared_with])}

          updated_secrets =
            Enum.map(secrets, fn s ->
              if s.id == secret_id, do: updated_secret, else: s
            end)

          :ets.insert(@table, {owner_id, updated_secrets})

          # Give the target a copy as "known secret"
          store_known_secret(target_id, owner_id, updated_secret)

          {:ok, updated_secret}
        else
          {:denied, :insufficient_trust}
        end
    end
  end

  @doc "Check if an agent would share secrets at a given trust level."
  @spec shareable_secrets(String.t(), float()) :: [map()]
  def shareable_secrets(agent_id, trust_level) do
    get_secrets(agent_id)
    |> Enum.filter(&(ensure_float(trust_level) >= ensure_float(&1.trust_threshold)))
  end

  @doc "Get all secrets an agent holds."
  @spec get_secrets(String.t()) :: [map()]
  def get_secrets(agent_id) do
    init()

    case :ets.lookup(@table, agent_id) do
      [{_, secrets}] -> secrets
      [] -> []
    end
  end

  @doc "Get count of secrets an agent holds."
  @spec secret_count(String.t()) :: integer()
  def secret_count(agent_id) do
    length(get_secrets(agent_id))
  end

  # ── Helpers ────────────────────────────────────────────

  defp store_known_secret(target_id, source_id, secret) do
    known = %{
      id: secret.id,
      content: secret.content,
      category: secret.category,
      source_id: source_id,
      # Known secrets require higher trust to re-share
      trust_threshold: 0.8,
      shared_with: [],
      created_at: System.system_time(:second)
    }

    existing = get_secrets(target_id)
    # Don't duplicate
    unless Enum.any?(existing, &(&1.id == secret.id)) do
      updated = Enum.take([known | existing], @max_secrets)
      :ets.insert(@table, {target_id, updated})
    end
  end
end
