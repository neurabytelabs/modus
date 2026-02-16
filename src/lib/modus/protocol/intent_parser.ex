defmodule Modus.Protocol.IntentParser do
  @moduledoc "Parses user messages into structured intents using keyword matching"

  @doc "Parse a user message into a structured intent."
  def parse(text) do
    text_lower = String.downcase(text)

    cond do
      Regex.match?(~r/(where|location|coordinates)/i, text_lower) ->
        {:query, :location}

      Regex.match?(~r/(how are|status|energy)/i, text_lower) ->
        {:query, :status}

      Regex.match?(~r/(friend|know|relationship)/i, text_lower) ->
        {:query, :relationships}

      String.contains?(text_lower, [" and ", " then "]) ->
        {:multi, parse_multi(text)}

      (match = Regex.run(~r/(north\w*|south\w*|east\w*|west\w*)\s*(go|move|walk)|(go|move|walk)\s+(north\w*|south\w*|east\w*|west\w*)/i, text_lower)) != nil ->
        # Direction could be in capture 1 or capture 4
        dir_raw = Enum.find([Enum.at(match, 1), Enum.at(match, 4)], &(&1 != nil and &1 != ""))
        direction = parse_direction(dir_raw)
        {:command, :move, direction}

      Regex.match?(~r/(stop|wait|halt)/i, text_lower) ->
        {:command, :stop}

      true ->
        {:chat, text}
    end
  end

  def parse_multi(text) do
    text
    |> String.split(~r/\s+(and|then)\s+/i)
    |> Enum.map(&parse/1)
    |> Enum.reject(fn
      {:multi, _} -> true
      _ -> false
    end)
  end

  defp parse_direction(dir) do
    d = String.downcase(dir)
    cond do
      String.starts_with?(d, "north") -> :north
      String.starts_with?(d, "south") -> :south
      String.starts_with?(d, "east") -> :east
      String.starts_with?(d, "west") -> :west
      true -> :north
    end
  end
end
