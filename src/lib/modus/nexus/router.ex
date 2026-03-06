defmodule Modus.Nexus.Router do
  @moduledoc """
  NexusRouter — Classifies chat messages into intents.
  Pure Elixir, no LLM. Pattern matching + keyword based.

  Intent types:
  - :insight (question) — sub: agent_query, event_query, stats_query, why_query
  - :action (command) — sub: terrain_modify, spawn_entity, config_change, rule_inject
  - :chat (conversation) — sub: greeting, farewell, general
  """

  @type intent :: :insight | :action | :chat
  @type sub_intent ::
          :agent_query | :event_query | :stats_query | :why_query |
          :terrain_modify | :spawn_entity | :config_change | :rule_inject |
          :greeting | :farewell | :general

  @type classification :: %{
          intent: intent(),
          sub_intent: sub_intent(),
          confidence: float(),
          raw: String.t()
        }

  # Keywords for intent detection
  @insight_question_words ~w(what where how who which when why)
  @insight_stats_words ~w(stats average total count most)
  @insight_event_words ~w(event events last happened log)
  @insight_why_words ~w(why reason explain)
  @insight_agent_words ~w(agent agents energy position affect mood happy sad)

  @action_terrain_words ~w(biome terrain modify change ocean forest desert)
  @action_spawn_words ~w(spawn create agent animal)
  @action_config_words ~w(config speed decay rate difficulty)
  @action_rule_words ~w(rule inject ban allow)

  @greeting_words ~w(hello hi hey hola)
  @farewell_words ~w(bye goodbye farewell)

  @doc "Classify a chat message into intent + sub_intent"
  @spec classify(String.t()) :: classification()
  def classify(message) when is_binary(message) do
    msg = message |> String.trim() |> String.downcase()
    tokens = tokenize(msg)

    cond do
      greeting?(tokens) ->
        result(:chat, :greeting, 0.9, message)

      farewell?(tokens) ->
        result(:chat, :farewell, 0.9, message)

      action_match = action_classify(tokens) ->
        action_match |> Map.put(:raw, message)

      insight_match = insight_classify(msg, tokens) ->
        insight_match |> Map.put(:raw, message)

      question_mark?(msg) ->
        result(:insight, :agent_query, 0.5, message)

      true ->
        result(:chat, :general, 0.7, message)
    end
  end

  def classify(_), do: result(:chat, :general, 0.3, "")

  @doc "Dispatch an insight classification to InsightEngine and return formatted response."
  @spec dispatch(classification()) :: String.t()
  def dispatch(%{intent: :insight, sub_intent: sub_intent, raw: raw}) do
    alias Modus.Nexus.InsightEngine

    {sub, data} =
      case sub_intent do
        :agent_query ->
          agent_id = extract_agent_id(raw)

          case InsightEngine.agent_query(agent_id) do
            {:error, _} = err -> {:agent_query, %{error: err, query: raw}}
            data -> {:agent_query, data}
          end

        :event_query ->
          {:event_query, InsightEngine.event_replay(limit: 10)}

        :stats_query ->
          {:stats_query, InsightEngine.stats_query()}

        :why_query ->
          agent_id = extract_agent_id(raw)
          answer = Modus.Nexus.TraceEngine.why_query(agent_id, raw)
          {:why_query, %{answer: answer, query: raw}}

        other ->
          {other, %{query: raw}}
      end

    InsightEngine.format_response(sub, data)
  end

  def dispatch(%{intent: :action, sub_intent: sub_intent, raw: raw}) do
    alias Modus.Nexus.ActionEngine

    params = ActionEngine.parse_params(sub_intent, raw)

    case ActionEngine.execute(sub_intent, params) do
      {:ok, msg} -> msg
      {:error, msg} -> msg
      {:confirm, msg} -> msg
    end
  end

  def dispatch(%{intent: intent}) do
    "⚠️ dispatch only handles :insight/:action intents, got :#{intent}"
  end

  defp extract_agent_id(raw) do
    # Try to find an agent by matching name from the message
    alias Modus.Simulation.{Agent, AgentSupervisor}

    ids = AgentSupervisor.list_agents()

    found =
      Enum.find(ids, fn id ->
        try do
          agent = Agent.get_state(id)
          name_lower = String.downcase(agent.name)
          String.contains?(String.downcase(raw), name_lower)
        catch
          :exit, _ -> false
        end
      end)

    found || List.first(ids) || "unknown"
  end

  # --- Private ---

  defp tokenize(msg) do
    msg
    |> String.replace(~r/[^\w\s]/u, " ")
    |> String.split(~r/\s+/, trim: true)
  end

  defp question_mark?(msg), do: String.contains?(msg, "?")

  defp greeting?(tokens), do: Enum.any?(tokens, &(&1 in @greeting_words))
  defp farewell?(tokens), do: Enum.any?(tokens, &(&1 in @farewell_words))

  defp action_classify(tokens) do
    # Score each sub-intent, pick highest
    scores = [
      {:spawn_entity, score_tokens(tokens, @action_spawn_words)},
      {:terrain_modify, score_tokens(tokens, @action_terrain_words)},
      {:config_change, score_tokens(tokens, @action_config_words)},
      {:rule_inject, score_tokens(tokens, @action_rule_words)}
    ]

    has_verb = has_action_verb?(tokens)
    {best_sub, best_score} = Enum.max_by(scores, &elem(&1, 1))

    cond do
      best_score >= 1 and has_verb ->
        result(:action, best_sub, 0.8, "")

      best_score >= 2 ->
        result(:action, best_sub, 0.7, "")

      true ->
        nil
    end
  end

  defp score_tokens(tokens, words) do
    Enum.count(tokens, &(&1 in words))
  end

  defp insight_classify(msg, tokens) do
    is_question = question_mark?(msg) or match_any?(tokens, @insight_question_words)

    if is_question do
      # Score-based: pick the sub-intent with most keyword matches
      scores = [
        {:why_query, match_count(tokens, @insight_why_words)},
        {:stats_query, match_count(tokens, @insight_stats_words)},
        {:event_query, match_count(tokens, @insight_event_words)},
        {:agent_query, match_count(tokens, @insight_agent_words)}
      ]

      {best_sub, best_score} = Enum.max_by(scores, &elem(&1, 1))

      if best_score > 0 do
        result(:insight, best_sub, 0.8, "")
      else
        result(:insight, :agent_query, 0.6, "")
      end
    else
      nil
    end
  end

  @action_verbs ~w(spawn create add remove delete modify change set inject)
  defp has_action_verb?(tokens), do: match_any?(tokens, @action_verbs)

  defp match_any?(tokens, words), do: Enum.any?(tokens, &(&1 in words))

  defp match_count(tokens, words) do
    Enum.count(tokens, &(&1 in words))
  end

  defp result(intent, sub_intent, confidence, raw) do
    %{intent: intent, sub_intent: sub_intent, confidence: confidence, raw: raw}
  end
end
