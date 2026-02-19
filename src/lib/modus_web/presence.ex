defmodule ModusWeb.Presence do
  @moduledoc """
  Phoenix.Presence for tracking connected viewers.

  Used by DemoLive to show real-time viewer count in the demo banner.
  """
  use Phoenix.Presence,
    otp_app: :modus,
    pubsub_server: Modus.PubSub
end
