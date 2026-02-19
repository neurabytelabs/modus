defmodule ModusWeb.CommandPalette do
  @moduledoc """
  Command Palette registry — all available commands for Cmd+K palette.
  v8.1.0
  """

  @commands [
    # 🎮 Simulation Control
    %{id: "sim_toggle", label: "Toggle Pause/Resume", category: "Simulation", icon: "⏯️", shortcut: "Space", action: "toggle_simulation"},
    %{id: "sim_pause", label: "Pause Simulation", category: "Simulation", icon: "⏸", shortcut: nil, action: "pause"},
    %{id: "sim_resume", label: "Resume Simulation", category: "Simulation", icon: "▶", shortcut: nil, action: "start"},
    %{id: "speed_1x", label: "Speed 1x", category: "Simulation", icon: "🐢", shortcut: "1", action: "set_speed_1"},
    %{id: "speed_5x", label: "Speed 5x", category: "Simulation", icon: "🐇", shortcut: "5", action: "set_speed_5"},
    %{id: "speed_10x", label: "Speed 10x", category: "Simulation", icon: "⚡", shortcut: "0", action: "set_speed_10"},
    %{id: "reset", label: "Reset World", category: "Simulation", icon: "↻", shortcut: nil, action: "reset"},

    # 👤 Agents
    %{id: "find_agent", label: "Find Agent...", category: "Agents", icon: "🔍", shortcut: nil, action: "palette_find_agent"},
    %{id: "spawn_agents", label: "Spawn Agents", category: "Agents", icon: "➕", shortcut: nil, action: "palette_spawn"},
    %{id: "list_agents", label: "List All Agents", category: "Agents", icon: "📋", shortcut: nil, action: "palette_list_agents"},
    %{id: "agent_designer", label: "Agent Designer", category: "Agents", icon: "🧑‍🎨", shortcut: nil, action: "toggle_agent_designer"},

    # 🌍 World
    %{id: "weather_clear", label: "Weather: Clear", category: "World", icon: "☀️", shortcut: nil, action: "palette_weather_clear"},
    %{id: "weather_rain", label: "Weather: Rain", category: "World", icon: "🌧️", shortcut: nil, action: "palette_weather_rain"},
    %{id: "weather_storm", label: "Weather: Storm", category: "World", icon: "⛈️", shortcut: nil, action: "palette_weather_storm"},
    %{id: "weather_snow", label: "Weather: Snow", category: "World", icon: "❄️", shortcut: nil, action: "palette_weather_snow"},
    %{id: "event_earthquake", label: "Event: Earthquake", category: "World", icon: "🌋", shortcut: nil, action: "palette_event_earthquake"},
    %{id: "event_festival", label: "Event: Festival", category: "World", icon: "🎉", shortcut: nil, action: "palette_event_festival"},
    %{id: "event_plague", label: "Event: Plague", category: "World", icon: "☠️", shortcut: nil, action: "palette_event_plague"},
    %{id: "season_spring", label: "Season: Spring", category: "World", icon: "🌸", shortcut: nil, action: "palette_season_spring"},
    %{id: "season_summer", label: "Season: Summer", category: "World", icon: "☀️", shortcut: nil, action: "palette_season_summer"},
    %{id: "season_autumn", label: "Season: Autumn", category: "World", icon: "🍂", shortcut: nil, action: "palette_season_autumn"},
    %{id: "season_winter", label: "Season: Winter", category: "World", icon: "❄️", shortcut: nil, action: "palette_season_winter"},

    # 🖥️ UI Panels
    %{id: "dashboard", label: "Analytics Dashboard", category: "UI", icon: "📊", shortcut: "D", action: "palette_dashboard"},
    %{id: "observatory", label: "Observatory", category: "UI", icon: "🔭", shortcut: nil, action: "open_stats"},
    %{id: "mind_view", label: "Mind View", category: "UI", icon: "🧠", shortcut: nil, action: "toggle_mind_view"},
    %{id: "settings", label: "Settings", category: "UI", icon: "⚙️", shortcut: nil, action: "open_settings"},
    %{id: "zen_mode", label: "Zen Mode", category: "UI", icon: "🧘", shortcut: "Z", action: "toggle_zen_mode"},
    %{id: "debug", label: "Performance Monitor", category: "UI", icon: "🐛", shortcut: nil, action: "toggle_perf_monitor"},
    %{id: "god_mode", label: "God Mode", category: "UI", icon: "👁️", shortcut: "G", action: "toggle_god_mode"},
    %{id: "cinematic", label: "Cinematic Camera", category: "UI", icon: "🎬", shortcut: "C", action: "toggle_cinematic"},
    %{id: "build_mode", label: "Build Mode", category: "UI", icon: "🔨", shortcut: "B", action: "toggle_build_mode"},
    %{id: "divine", label: "Divine Intervention", category: "UI", icon: "⚡👑", shortcut: nil, action: "toggle_divine_panel"},
    %{id: "timeline", label: "Story Timeline", category: "UI", icon: "📜", shortcut: nil, action: "toggle_timeline"},
    %{id: "event_timeline", label: "Event Timeline", category: "UI", icon: "🔔", shortcut: nil, action: "toggle_event_timeline"},
    %{id: "llm_metrics", label: "LLM Metrics", category: "UI", icon: "⚡", shortcut: "M", action: "toggle_llm_metrics"},
    %{id: "history", label: "World History", category: "UI", icon: "📖", shortcut: nil, action: "open_history"},
    %{id: "rules", label: "World Rules", category: "UI", icon: "🎛️", shortcut: nil, action: "open_rules"},

    # 💾 World Management
    %{id: "save", label: "Save World", category: "Save/Load", icon: "💾", shortcut: nil, action: "open_save_load"},
    %{id: "export", label: "Export World", category: "Save/Load", icon: "📤", shortcut: nil, action: "open_export"},
    %{id: "screenshot", label: "Screenshot", category: "Save/Load", icon: "📸", shortcut: "P", action: "screenshot_with_overlay"},
    %{id: "gallery", label: "Universe Gallery", category: "Save/Load", icon: "🌍", shortcut: nil, action: "dashboard_back"},

    # 🔍 Query
    %{id: "stats", label: "World Statistics", category: "Query", icon: "📈", shortcut: nil, action: "open_stats"},
  ]

  def all_commands, do: @commands

  def search(query) when query in [nil, ""], do: @commands

  def search(query) do
    q = String.downcase(query)
    Enum.filter(@commands, fn cmd ->
      String.contains?(String.downcase(cmd.label), q) ||
      String.contains?(String.downcase(cmd.category), q) ||
      String.contains?(String.downcase(cmd.id), q)
    end)
  end
end
