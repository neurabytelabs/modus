defmodule ModusWeb.Endpoint do
  @moduledoc "ModusWeb.Endpoint — auto-documented by Probatio quality pass."
  use Phoenix.Endpoint, otp_app: :modus

  @session_options [
    store: :cookie,
    key: "_modus_key",
    signing_salt: "modus_salt",
    same_site: "Lax"
  ]

  socket("/socket", ModusWeb.UserSocket,
    websocket: true,
    longpoll: true
  )

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static,
    at: "/",
    from: :modus,
    gzip: false,
    only: ModusWeb.static_paths()
  )

  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(ModusWeb.Router)
end
