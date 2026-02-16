defmodule Modus.Intelligence.GeminiClient do
  @moduledoc "Direct Gemini REST API client — fallback when Antigravity is down."
  require Logger

  @api_key "***REMOVED***"
  @model "gemini-2.0-flash"
  @timeout 30_000

  def chat(messages) do
    url = "https://generativelanguage.googleapis.com/v1beta/models/#{@model}:generateContent?key=#{@api_key}"

    # Convert OpenAI format messages to Gemini format
    {system_text, conversation} = extract_system(messages)

    contents = Enum.map(conversation, fn msg ->
      role = if msg[:role] == "assistant" || msg["role"] == "assistant", do: "model", else: "user"
      content = msg[:content] || msg["content"]
      %{"role" => role, "parts" => [%{"text" => content}]}
    end)

    body = %{"contents" => contents}
    body = if system_text, do: Map.put(body, "systemInstruction", %{"parts" => [%{"text" => system_text}]}), else: body

    case Req.post(url,
           json: body,
           receive_timeout: @timeout,
           finch: Modus.Finch
         ) do
      {:ok, %{status: 200, body: resp}} ->
        text = get_in(resp, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
        if text, do: {:ok, text}, else: {:error, :no_content}
      {:ok, %{status: status, body: resp_body}} ->
        Logger.warning("GeminiClient failed: #{status}")
        {:error, {:http, status, inspect(resp_body)}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_system(messages) do
    system = Enum.find(messages, fn m -> (m[:role] || m["role"]) == "system" end)
    rest = Enum.reject(messages, fn m -> (m[:role] || m["role"]) == "system" end)
    {system && (system[:content] || system["content"]), rest}
  end
end
