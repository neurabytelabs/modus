defmodule ModusWeb.UserSocket do
  @moduledoc "ModusWeb.UserSocket — auto-documented by Probatio quality pass."
  use Phoenix.Socket

  channel("world:*", ModusWeb.WorldChannel)

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
