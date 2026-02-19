defmodule Modus.Protocol.IntentParser do
  @moduledoc "Parses user messages into structured intents using keyword matching"

  @doc "Parse a user message into a structured intent."
  def parse(text) do
    text_lower = String.downcase(text)

    cond do
      # God mode intents (checked first — highest priority)
      (god_intent = parse_god_mode(text_lower, text)) != nil ->
        god_intent

      Regex.match?(~r/(where|location|coordinates|neredesin)/i, text_lower) ->
        {:query, :location}

      Regex.match?(~r/(how are|status|energy|nasılsın)/i, text_lower) ->
        {:query, :status}

      Regex.match?(~r/(friend|know|relationship|arkadaş)/i, text_lower) ->
        {:query, :relationships}

      String.contains?(text_lower, [" and ", " then ", " ve "]) ->
        {:multi, parse_multi(text)}

      (match =
         Regex.run(
           ~r/(north\w*|south\w*|east\w*|west\w*|kuzey\w*|güney\w*|doğu\w*|batı\w*)\s*(go|move|walk|git)|(go|move|walk|git)\s+(north\w*|south\w*|east\w*|west\w*|kuzey\w*|güney\w*|doğu\w*|batı\w*)/i,
           text_lower
         )) != nil ->
        dir_raw = Enum.find([Enum.at(match, 1), Enum.at(match, 4)], &(&1 != nil and &1 != ""))
        direction = parse_direction(dir_raw)
        {:command, :move, direction}

      Regex.match?(~r/(stop|wait|halt|dur\b)/i, text_lower) ->
        {:command, :stop}

      true ->
        {:chat, text}
    end
  end

  def parse_multi(text) do
    text
    |> String.split(~r/\s+(and|then|ve)\s+/i)
    |> Enum.map(&parse/1)
    |> Enum.reject(fn
      {:multi, _} -> true
      _ -> false
    end)
  end

  # ── God Mode Intent Parsing ──────────────────────────────────

  @doc "Parse god-mode commands from natural language. Returns nil if not a god-mode intent."
  @spec parse_god_mode(String.t(), String.t()) :: god_mode_intent | nil
        when god_mode_intent:
               {:god_mode, :weather_event, map()}
               | {:god_mode, :spawn_entity, map()}
               | {:god_mode, :terrain_modify, map()}
               | {:god_mode, :config_change, map()}
               | {:god_mode, :rule_inject, map()}
  def parse_god_mode(text_lower, _original) do
    cond do
      # Weather events
      (weather = parse_weather_intent(text_lower)) != nil ->
        weather

      # Spawn entities
      (spawn = parse_spawn_intent(text_lower)) != nil ->
        spawn

      # Terrain modification
      (terrain = parse_terrain_intent(text_lower)) != nil ->
        terrain

      # Config changes
      (config = parse_config_intent(text_lower)) != nil ->
        config

      # Rule injection
      (rule = parse_rule_intent(text_lower)) != nil ->
        rule

      true ->
        nil
    end
  end

  defp parse_weather_intent(text) do
    weather_patterns = [
      {~r/(send|trigger|start|summon|invoke|gönder|başlat)\s+(an?\s+)?(massive\s+|huge\s+|strong\s+|mild\s+|light\s+|büyük\s+|güçlü\s+|hafif\s+)?(storm|fırtına|thunderstorm)/, :storm},
      {~r/(send|trigger|start|gönder|başlat)\s+(an?\s+)?(massive\s+|huge\s+|strong\s+|mild\s+|light\s+)?(rain|yağmur)/, :rain},
      {~r/(send|trigger|start|gönder|başlat)\s+(an?\s+)?(massive\s+|huge\s+|strong\s+|mild\s+|light\s+)?(flood|sel)/, :flood},
      {~r/(send|trigger|start|gönder|başlat)\s+(an?\s+)?(massive\s+|huge\s+|strong\s+|mild\s+|light\s+)?(drought|kuraklık)/, :drought},
      {~r/(send|trigger|start|gönder|başlat)\s+(an?\s+)?(massive\s+|huge\s+|strong\s+|mild\s+|light\s+)?(fire|yangın|ateş)/, :fire},
      {~r/(send|trigger|start|gönder|başlat)\s+(an?\s+)?(massive\s+|huge\s+|strong\s+|mild\s+|light\s+)?(earthquake|deprem)/, :earthquake},
      {~r/(send|trigger|start|gönder|başlat)\s+(an?\s+)?(massive\s+|huge\s+|strong\s+|mild\s+|light\s+)?(meteor|göktaşı)/, :meteor_shower},
      {~r/(send|trigger|start|gönder|başlat)\s+(an?\s+)?(massive\s+|huge\s+|strong\s+|mild\s+|light\s+)?(blizzard|tipi|kar fırtınası)/, :blizzard},
      {~r/(send|trigger|start|gönder|başlat)\s+(an?\s+)?(massive\s+|huge\s+|strong\s+|mild\s+|light\s+)?(heatwave|sıcak dalgası)/, :heatwave},
      {~r/(send|trigger|start|gönder|başlat)\s+(an?\s+)?(massive\s+|huge\s+|strong\s+|mild\s+|light\s+)?(festival|şenlik)/, :festival},
      {~r/(clear weather|hava\s*yı\s*aç|güneş\s*gönder)/, :clear},
      {~r/fırtına\s+gönder/, :storm},
      {~r/yağmur\s+yağdır/, :rain},
      {~r/deprem\s+yap/, :earthquake},
      {~r/sel\s+gönder/, :flood}
    ]

    Enum.find_value(weather_patterns, fn {pattern, event} ->
      if Regex.match?(pattern, text) do
        severity = parse_severity(text)
        {:god_mode, :weather_event, %{event: event, severity: severity}}
      end
    end)
  end

  defp parse_spawn_intent(text) do
    patterns = [
      ~r/(spawn|create|summon|oluştur|yarat)\s+(\d+)\s*(agent|agents|ajan|ajanlar)/,
      ~r/(spawn|create|summon|oluştur|yarat)\s+(an?\s+)?(agent|ajan)/
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, _verb, count_str, _] ->
          count = parse_integer(count_str)
          {:god_mode, :spawn_entity, %{count: count}}

        [_, _verb, _, _entity] ->
          {:god_mode, :spawn_entity, %{count: 1}}

        _ ->
          nil
      end
    end)
  end

  defp parse_terrain_intent(text) do
    patterns = [
      ~r/(change|set|modify|transform|değiştir|dönüştür)\s+(terrain|arazi|biome)\s+(to|into|olarak)?\s*(desert|forest|water|mountain|grass|swamp|tundra|sand|çöl|orman|su|dağ|çimen|bataklık)/,
      ~r/(make|turn)\s+(it|the\s+land|everything)\s+(into\s+)?(desert|forest|water|mountain|grass|swamp|tundra|sand)/,
      ~r/arazi\s*yı?\s*(çöl|orman|su|dağ|çimen|bataklık)\s*(yap|değiştir)/
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        matches when is_list(matches) and length(matches) >= 2 ->
          terrain = List.last(matches)
          {:god_mode, :terrain_modify, %{terrain: terrain}}

        _ ->
          nil
      end
    end)
  end

  defp parse_config_intent(text) do
    config_patterns = [
      {~r/(set|change|modify)\s+(time\s*speed|hız)\s+(to\s+)?(\d+\.?\d*)/, :time_speed},
      {~r/(set|change|modify)\s+(danger\s*level|tehlike)\s+(to\s+)?(peaceful|moderate|harsh|extreme)/, :danger_level},
      {~r/(set|change|modify)\s+(birth\s*rate|doğum\s*oranı)\s+(to\s+)?(\d+\.?\d*)/, :birth_rate},
      {~r/hız\s*ı?\s*(\d+\.?\d*)\s*(yap|ayarla)/, :time_speed}
    ]

    Enum.find_value(config_patterns, fn {pattern, key} ->
      case Regex.run(pattern, text) do
        matches when is_list(matches) and length(matches) >= 2 ->
          value_str = List.last(matches)
          value = parse_config_value(key, value_str)
          {:god_mode, :config_change, %{key: key, value: value}}

        _ ->
          nil
      end
    end)
  end

  defp parse_rule_intent(text) do
    preset_patterns = [
      {~r/(apply|use|activate|uygula)\s+(preset|kural)\s+["']?(.+?)["']?$/, 3},
      {~r/(peaceful paradise|harsh survival|chaotic|utopia|evolution lab)/i, 1}
    ]

    Enum.find_value(preset_patterns, fn {pattern, group_idx} ->
      case Regex.run(pattern, text) do
        matches when is_list(matches) ->
          preset = Enum.at(matches, group_idx) |> String.trim() |> titlecase_preset()
          {:god_mode, :rule_inject, %{preset: preset}}

        _ ->
          nil
      end
    end)
  end

  defp parse_severity(text) do
    cond do
      Regex.match?(~r/(massive|huge|devastating|büyük|devasa)/i, text) -> 3
      Regex.match?(~r/(strong|powerful|güçlü)/i, text) -> 2
      Regex.match?(~r/(mild|small|light|hafif|küçük)/i, text) -> 1
      true -> 2
    end
  end

  defp parse_integer(str) do
    case Integer.parse(String.trim(str)) do
      {n, _} -> max(n, 1)
      :error -> 1
    end
  end

  defp parse_config_value(key, value_str) when key in [:time_speed, :birth_rate] do
    case Float.parse(value_str) do
      {f, _} -> f
      :error -> 1.0
    end
  end

  defp parse_config_value(:danger_level, value_str) do
    case String.downcase(value_str) do
      "peaceful" -> :peaceful
      "moderate" -> :moderate
      "harsh" -> :harsh
      "extreme" -> :extreme
      _ -> :moderate
    end
  end

  defp parse_config_value(_key, value_str), do: value_str

  defp titlecase_preset(name) do
    name
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp parse_direction(dir) do
    d = String.downcase(dir)

    cond do
      String.starts_with?(d, "north") or String.starts_with?(d, "kuzey") -> :north
      String.starts_with?(d, "south") or String.starts_with?(d, "güney") -> :south
      String.starts_with?(d, "east") or String.starts_with?(d, "doğu") -> :east
      String.starts_with?(d, "west") or String.starts_with?(d, "batı") -> :west
      true -> :north
    end
  end
end
