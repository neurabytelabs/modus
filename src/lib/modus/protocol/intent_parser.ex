defmodule Modus.Protocol.IntentParser do
  @moduledoc "Parses user messages into structured intents using keyword matching"

  @doc "Parse a user message into a structured intent."
  def parse(text) do
    text_lower = String.downcase(text)

    cond do
      Regex.match?(~r/(where|location|coordinates|neredesin)/i, text_lower) ->
        {:query, :location}

      Regex.match?(~r/(how are|status|energy|nasılsın)/i, text_lower) ->
        {:query, :status}

      Regex.match?(~r/(friend|know|relationship|arkadaş)/i, text_lower) ->
        {:query, :relationships}

      String.contains?(text_lower, [" and ", " then ", " ve "]) ->
        {:multi, parse_multi(text)}

      (match = Regex.run(~r/(north\w*|south\w*|east\w*|west\w*|kuzey\w*|güney\w*|doğu\w*|batı\w*)\s*(go|move|walk|git)|(go|move|walk|git)\s+(north\w*|south\w*|east\w*|west\w*|kuzey\w*|güney\w*|doğu\w*|batı\w*)/i, text_lower)) != nil ->
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
