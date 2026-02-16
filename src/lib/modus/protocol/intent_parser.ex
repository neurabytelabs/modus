defmodule Modus.Protocol.IntentParser do
  @moduledoc "Parses user messages into structured intents using keyword matching"

  @doc "Parse a user message into a structured intent."
  def parse(text) do
    text_lower = String.downcase(text)

    cond do
      Regex.match?(~r/(nerede|konum|koordinat|where)/i, text_lower) ->
        {:query, :location}

      Regex.match?(~r/(nasıl|durum|enerji|how are|status)/i, text_lower) ->
        {:query, :status}

      Regex.match?(~r/(tanı|arkadaş|ilişki|friend|know)/i, text_lower) ->
        {:query, :relationships}

      (match = Regex.run(~r/(kuzey\w*|güney\w*|doğu\w*|batı\w*|north\w*|south\w*|east\w*|west\w*)\s*(git|yürü|go|move)|(git|yürü|go|move)\s+(kuzey\w*|güney\w*|doğu\w*|batı\w*|north\w*|south\w*|east\w*|west\w*)/i, text_lower)) != nil ->
        # Direction could be in capture 1 or capture 4
        dir_raw = Enum.find([Enum.at(match, 1), Enum.at(match, 4)], &(&1 != nil and &1 != ""))
        direction = parse_direction(dir_raw)
        {:command, :move, direction}

      Regex.match?(~r/(dur|bekle|stop|wait)/i, text_lower) ->
        {:command, :stop}

      true ->
        {:chat, text}
    end
  end

  defp parse_direction(dir) do
    d = String.downcase(dir)
    cond do
      String.starts_with?(d, "kuzey") or String.starts_with?(d, "north") -> :north
      String.starts_with?(d, "güney") or String.starts_with?(d, "south") -> :south
      String.starts_with?(d, "doğu") or String.starts_with?(d, "east") -> :east
      String.starts_with?(d, "batı") or String.starts_with?(d, "west") -> :west
      true -> :north
    end
  end
end
