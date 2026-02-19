defmodule ModusWeb.Router do
  @moduledoc "ModusWeb.Router — auto-documented by Probatio quality pass."
  use ModusWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {ModusWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", ModusWeb do
    pipe_through(:browser)

    live("/", UniverseLive, :index)
    live("/demo", DemoLive, :index)
  end

  if Mix.env() in [:dev] do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)
      live_dashboard("/dashboard", metrics: ModusWeb.Telemetry)
    end
  end
end
