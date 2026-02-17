defmodule Modus.Simulation.WorldTemplates do
  @moduledoc """
  Data-driven world templates for MODUS.

  Each template defines terrain distribution, resource density, danger level,
  default occupations, color palette (for 8×8 thumbnail preview), and wildlife types.

  In Spinoza's terms, each template is a distinct "attribute" through which
  Substance expresses itself — the same underlying reality, perceived differently.
  """

  @type template :: %{
          id: String.t(),
          name: String.t(),
          emoji: String.t(),
          desc: String.t(),
          difficulty: :easy | :medium | :hard | :extreme,
          terrain: %{
            grass: float(),
            forest: float(),
            water: float(),
            mountain: float(),
            sand: float(),
            desert: float()
          },
          resource_density: :sparse | :medium | :abundant,
          danger_level: :peaceful | :normal | :dangerous | :extreme,
          occupations: [atom()],
          wildlife: [atom()],
          # 64-element list (8×8) of Tailwind bg color classes for thumbnail preview
          thumb_grid: [String.t()]
        }

  @templates [
    %{
      id: "village",
      name: "Village",
      emoji: "🏘️",
      desc: "Peaceful plains with forests and farmland",
      difficulty: :easy,
      terrain: %{grass: 0.45, forest: 0.25, water: 0.15, mountain: 0.10, sand: 0.0, desert: 0.05},
      resource_density: :abundant,
      danger_level: :peaceful,
      occupations: [:farmer, :builder, :healer, :trader, :explorer],
      wildlife: [:deer, :rabbit, :bird, :fish],
      thumb_grid: [
        # Row 0
        "bg-green-800", "bg-green-800", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-800", "bg-green-800",
        # Row 1
        "bg-green-800", "bg-green-600", "bg-green-600", "bg-amber-700", "bg-amber-700", "bg-green-600", "bg-green-600", "bg-green-800",
        # Row 2
        "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600",
        # Row 3
        "bg-green-600", "bg-green-600", "bg-blue-500", "bg-blue-500", "bg-blue-500", "bg-green-600", "bg-green-600", "bg-green-600",
        # Row 4
        "bg-green-600", "bg-green-600", "bg-blue-500", "bg-green-600", "bg-green-600", "bg-green-600", "bg-amber-700", "bg-green-600",
        # Row 5
        "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-amber-700", "bg-green-600",
        # Row 6
        "bg-green-800", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-800",
        # Row 7
        "bg-green-800", "bg-green-800", "bg-green-600", "bg-gray-500", "bg-gray-500", "bg-green-600", "bg-green-800", "bg-green-800"
      ]
    },
    %{
      id: "island",
      name: "Island",
      emoji: "🏝️",
      desc: "Surrounded by ocean, limited land mass",
      difficulty: :medium,
      terrain: %{grass: 0.30, forest: 0.15, water: 0.45, mountain: 0.05, sand: 0.05, desert: 0.0},
      resource_density: :medium,
      danger_level: :normal,
      occupations: [:farmer, :explorer, :trader, :healer, :builder],
      wildlife: [:fish, :bird, :rabbit, :deer],
      thumb_grid: [
        "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-blue-600",
        "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-yellow-400", "bg-yellow-400", "bg-blue-600", "bg-blue-600", "bg-blue-600",
        "bg-blue-600", "bg-blue-600", "bg-yellow-400", "bg-green-600", "bg-green-600", "bg-yellow-400", "bg-blue-600", "bg-blue-600",
        "bg-blue-600", "bg-yellow-400", "bg-green-600", "bg-green-800", "bg-green-600", "bg-green-600", "bg-yellow-400", "bg-blue-600",
        "bg-blue-600", "bg-yellow-400", "bg-green-600", "bg-green-600", "bg-green-800", "bg-green-600", "bg-yellow-400", "bg-blue-600",
        "bg-blue-600", "bg-blue-600", "bg-yellow-400", "bg-green-600", "bg-green-600", "bg-yellow-400", "bg-blue-600", "bg-blue-600",
        "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-yellow-400", "bg-yellow-400", "bg-blue-600", "bg-blue-600", "bg-blue-600",
        "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-blue-600", "bg-blue-600"
      ]
    },
    %{
      id: "desert",
      name: "Desert",
      emoji: "🏜️",
      desc: "Harsh terrain with scarce water and oases",
      difficulty: :hard,
      terrain: %{grass: 0.10, forest: 0.05, water: 0.05, mountain: 0.15, sand: 0.0, desert: 0.65},
      resource_density: :sparse,
      danger_level: :dangerous,
      occupations: [:explorer, :trader, :healer, :builder, :farmer],
      wildlife: [:rabbit, :bird],
      thumb_grid: [
        "bg-yellow-600", "bg-yellow-600", "bg-yellow-700", "bg-yellow-600", "bg-yellow-600", "bg-yellow-700", "bg-yellow-600", "bg-yellow-600",
        "bg-yellow-600", "bg-yellow-700", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600",
        "bg-yellow-700", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-gray-500", "bg-gray-500", "bg-yellow-600",
        "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-blue-500", "bg-yellow-600", "bg-gray-500", "bg-yellow-600", "bg-yellow-600",
        "bg-yellow-600", "bg-yellow-600", "bg-green-600", "bg-blue-500", "bg-green-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-700",
        "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-600",
        "bg-yellow-600", "bg-yellow-700", "bg-yellow-600", "bg-yellow-600", "bg-yellow-700", "bg-yellow-600", "bg-yellow-600", "bg-gray-500",
        "bg-yellow-600", "bg-yellow-600", "bg-yellow-600", "bg-yellow-700", "bg-yellow-600", "bg-yellow-600", "bg-gray-500", "bg-gray-500"
      ]
    },
    %{
      id: "space",
      name: "Space",
      emoji: "🚀",
      desc: "Alien world with crystal formations",
      difficulty: :extreme,
      terrain: %{grass: 0.15, forest: 0.10, water: 0.10, mountain: 0.20, sand: 0.0, desert: 0.45},
      resource_density: :sparse,
      danger_level: :extreme,
      occupations: [:explorer, :builder, :healer, :trader, :farmer],
      wildlife: [:bird],
      thumb_grid: [
        "bg-gray-800", "bg-gray-800", "bg-gray-900", "bg-gray-800", "bg-purple-800", "bg-gray-800", "bg-gray-900", "bg-gray-800",
        "bg-gray-800", "bg-purple-800", "bg-gray-800", "bg-gray-800", "bg-gray-800", "bg-gray-800", "bg-cyan-700", "bg-gray-800",
        "bg-gray-900", "bg-gray-800", "bg-gray-800", "bg-cyan-700", "bg-gray-800", "bg-gray-800", "bg-gray-800", "bg-gray-900",
        "bg-gray-800", "bg-gray-800", "bg-cyan-700", "bg-cyan-700", "bg-gray-800", "bg-purple-800", "bg-gray-800", "bg-gray-800",
        "bg-gray-800", "bg-gray-800", "bg-gray-800", "bg-gray-800", "bg-purple-800", "bg-purple-800", "bg-gray-800", "bg-gray-800",
        "bg-gray-900", "bg-gray-800", "bg-purple-800", "bg-gray-800", "bg-gray-800", "bg-gray-800", "bg-gray-800", "bg-gray-900",
        "bg-gray-800", "bg-gray-800", "bg-gray-800", "bg-gray-800", "bg-gray-800", "bg-cyan-700", "bg-gray-800", "bg-gray-800",
        "bg-gray-800", "bg-gray-900", "bg-gray-800", "bg-cyan-700", "bg-gray-800", "bg-gray-800", "bg-gray-900", "bg-gray-800"
      ]
    },
    %{
      id: "underwater",
      name: "Underwater",
      emoji: "🌊",
      desc: "Ocean floor with coral reefs and trenches",
      difficulty: :hard,
      terrain: %{grass: 0.05, forest: 0.20, water: 0.50, mountain: 0.15, sand: 0.10, desert: 0.0},
      resource_density: :abundant,
      danger_level: :dangerous,
      occupations: [:explorer, :healer, :trader, :builder, :farmer],
      wildlife: [:fish, :bird],
      thumb_grid: [
        "bg-blue-800", "bg-blue-700", "bg-blue-800", "bg-blue-700", "bg-blue-800", "bg-blue-800", "bg-blue-700", "bg-blue-800",
        "bg-blue-700", "bg-blue-800", "bg-blue-700", "bg-blue-800", "bg-blue-700", "bg-blue-800", "bg-blue-800", "bg-blue-700",
        "bg-blue-800", "bg-blue-700", "bg-emerald-600", "bg-emerald-600", "bg-blue-700", "bg-blue-800", "bg-blue-700", "bg-blue-800",
        "bg-blue-700", "bg-emerald-600", "bg-emerald-500", "bg-pink-500", "bg-emerald-600", "bg-blue-700", "bg-blue-800", "bg-blue-700",
        "bg-blue-800", "bg-emerald-600", "bg-pink-500", "bg-emerald-500", "bg-emerald-600", "bg-blue-800", "bg-blue-700", "bg-blue-800",
        "bg-blue-700", "bg-blue-800", "bg-emerald-600", "bg-emerald-600", "bg-blue-700", "bg-slate-700", "bg-slate-700", "bg-blue-700",
        "bg-blue-800", "bg-blue-700", "bg-blue-800", "bg-blue-700", "bg-blue-800", "bg-slate-700", "bg-blue-800", "bg-blue-700",
        "bg-blue-800", "bg-blue-800", "bg-blue-700", "bg-blue-800", "bg-blue-800", "bg-blue-700", "bg-blue-800", "bg-blue-800"
      ]
    },
    %{
      id: "medieval",
      name: "Medieval",
      emoji: "🏰",
      desc: "Castles, farmland, and dense forests",
      difficulty: :medium,
      terrain: %{grass: 0.35, forest: 0.30, water: 0.10, mountain: 0.15, sand: 0.0, desert: 0.10},
      resource_density: :medium,
      danger_level: :normal,
      occupations: [:builder, :farmer, :trader, :healer, :explorer],
      wildlife: [:deer, :rabbit, :wolf, :bird],
      thumb_grid: [
        "bg-green-800", "bg-green-800", "bg-green-800", "bg-green-600", "bg-green-600", "bg-green-800", "bg-green-800", "bg-green-800",
        "bg-green-800", "bg-green-600", "bg-green-600", "bg-amber-700", "bg-amber-700", "bg-green-600", "bg-green-600", "bg-green-800",
        "bg-green-800", "bg-green-600", "bg-amber-700", "bg-amber-700", "bg-amber-700", "bg-amber-700", "bg-green-600", "bg-green-800",
        "bg-green-600", "bg-green-600", "bg-amber-700", "bg-gray-400", "bg-gray-400", "bg-amber-700", "bg-green-600", "bg-green-600",
        "bg-green-600", "bg-blue-500", "bg-blue-500", "bg-green-600", "bg-green-600", "bg-green-600", "bg-green-600", "bg-gray-500",
        "bg-green-800", "bg-green-600", "bg-blue-500", "bg-green-600", "bg-green-600", "bg-green-600", "bg-gray-500", "bg-gray-500",
        "bg-green-800", "bg-green-800", "bg-green-600", "bg-green-600", "bg-green-800", "bg-green-800", "bg-gray-500", "bg-gray-500",
        "bg-green-800", "bg-green-800", "bg-green-800", "bg-green-800", "bg-green-800", "bg-green-800", "bg-green-800", "bg-green-800"
      ]
    },
    %{
      id: "cyberpunk",
      name: "Cyberpunk",
      emoji: "🌃",
      desc: "Neon-lit urban sprawl with toxic zones",
      difficulty: :hard,
      terrain: %{grass: 0.10, forest: 0.05, water: 0.15, mountain: 0.20, sand: 0.0, desert: 0.50},
      resource_density: :medium,
      danger_level: :dangerous,
      occupations: [:trader, :builder, :explorer, :healer, :farmer],
      wildlife: [:bird, :rabbit],
      thumb_grid: [
        "bg-gray-900", "bg-gray-800", "bg-gray-900", "bg-purple-700", "bg-purple-700", "bg-gray-900", "bg-gray-800", "bg-gray-900",
        "bg-gray-800", "bg-fuchsia-600", "bg-gray-800", "bg-gray-900", "bg-gray-900", "bg-gray-800", "bg-cyan-500", "bg-gray-800",
        "bg-gray-900", "bg-gray-800", "bg-gray-900", "bg-gray-800", "bg-gray-900", "bg-gray-800", "bg-gray-900", "bg-gray-900",
        "bg-purple-700", "bg-gray-900", "bg-gray-800", "bg-fuchsia-600", "bg-cyan-500", "bg-gray-800", "bg-gray-900", "bg-gray-800",
        "bg-gray-800", "bg-gray-900", "bg-cyan-500", "bg-gray-800", "bg-gray-900", "bg-fuchsia-600", "bg-gray-800", "bg-gray-900",
        "bg-gray-900", "bg-gray-800", "bg-gray-900", "bg-gray-800", "bg-lime-500", "bg-lime-500", "bg-gray-900", "bg-gray-800",
        "bg-gray-800", "bg-cyan-500", "bg-gray-800", "bg-gray-900", "bg-lime-500", "bg-gray-800", "bg-gray-900", "bg-gray-800",
        "bg-gray-900", "bg-gray-800", "bg-gray-900", "bg-gray-800", "bg-gray-900", "bg-gray-800", "bg-gray-900", "bg-gray-900"
      ]
    },
    %{
      id: "jungle",
      name: "Jungle",
      emoji: "🌴",
      desc: "Dense tropical canopy with hidden rivers",
      difficulty: :medium,
      terrain: %{grass: 0.15, forest: 0.50, water: 0.20, mountain: 0.10, sand: 0.0, desert: 0.05},
      resource_density: :abundant,
      danger_level: :normal,
      occupations: [:explorer, :healer, :farmer, :builder, :trader],
      wildlife: [:bird, :deer, :rabbit, :fish],
      thumb_grid: [
        "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-800",
        "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900",
        "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-700", "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900",
        "bg-green-800", "bg-green-900", "bg-blue-500", "bg-blue-500", "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-800",
        "bg-green-900", "bg-green-800", "bg-green-900", "bg-blue-500", "bg-blue-500", "bg-green-700", "bg-green-800", "bg-green-900",
        "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-800",
        "bg-green-900", "bg-green-800", "bg-green-700", "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-900",
        "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-900", "bg-green-800", "bg-green-800"
      ]
    },
    %{
      id: "arctic",
      name: "Arctic",
      emoji: "❄️",
      desc: "Frozen tundra with ice sheets and scarce life",
      difficulty: :hard,
      terrain: %{grass: 0.10, forest: 0.10, water: 0.25, mountain: 0.20, sand: 0.0, desert: 0.35},
      resource_density: :sparse,
      danger_level: :dangerous,
      occupations: [:explorer, :healer, :builder, :trader, :farmer],
      wildlife: [:rabbit, :wolf, :fish, :bird],
      thumb_grid: [
        "bg-slate-200", "bg-slate-300", "bg-slate-200", "bg-slate-200", "bg-blue-300", "bg-blue-300", "bg-slate-200", "bg-slate-300",
        "bg-slate-300", "bg-slate-200", "bg-slate-200", "bg-slate-300", "bg-blue-300", "bg-slate-200", "bg-slate-200", "bg-slate-200",
        "bg-slate-200", "bg-slate-200", "bg-slate-300", "bg-slate-200", "bg-slate-200", "bg-slate-200", "bg-slate-300", "bg-slate-200",
        "bg-slate-300", "bg-slate-200", "bg-slate-200", "bg-slate-200", "bg-slate-300", "bg-slate-200", "bg-slate-200", "bg-gray-400",
        "bg-slate-200", "bg-blue-400", "bg-blue-400", "bg-slate-200", "bg-slate-200", "bg-slate-200", "bg-gray-400", "bg-gray-400",
        "bg-slate-200", "bg-slate-300", "bg-blue-400", "bg-slate-200", "bg-slate-300", "bg-green-800", "bg-green-800", "bg-gray-400",
        "bg-slate-300", "bg-slate-200", "bg-slate-200", "bg-slate-300", "bg-slate-200", "bg-green-800", "bg-slate-200", "bg-slate-300",
        "bg-slate-200", "bg-slate-200", "bg-slate-300", "bg-slate-200", "bg-slate-200", "bg-slate-200", "bg-slate-300", "bg-slate-200"
      ]
    },
    %{
      id: "volcanic",
      name: "Volcanic",
      emoji: "🌋",
      desc: "Lava flows, ash plains, and fertile valleys",
      difficulty: :extreme,
      terrain: %{grass: 0.15, forest: 0.10, water: 0.05, mountain: 0.35, sand: 0.0, desert: 0.35},
      resource_density: :medium,
      danger_level: :extreme,
      occupations: [:builder, :explorer, :healer, :farmer, :trader],
      wildlife: [:bird, :rabbit],
      thumb_grid: [
        "bg-gray-700", "bg-gray-700", "bg-gray-800", "bg-gray-700", "bg-gray-700", "bg-gray-800", "bg-gray-700", "bg-gray-700",
        "bg-gray-700", "bg-gray-800", "bg-gray-700", "bg-gray-700", "bg-gray-700", "bg-gray-700", "bg-gray-800", "bg-gray-700",
        "bg-gray-800", "bg-gray-700", "bg-gray-700", "bg-red-700", "bg-red-700", "bg-gray-700", "bg-gray-700", "bg-gray-800",
        "bg-gray-700", "bg-gray-700", "bg-red-700", "bg-orange-500", "bg-orange-500", "bg-red-700", "bg-gray-700", "bg-gray-700",
        "bg-gray-700", "bg-gray-700", "bg-red-700", "bg-orange-500", "bg-red-700", "bg-gray-700", "bg-gray-700", "bg-gray-700",
        "bg-gray-800", "bg-gray-700", "bg-gray-700", "bg-red-700", "bg-gray-700", "bg-green-600", "bg-green-600", "bg-gray-800",
        "bg-gray-700", "bg-gray-800", "bg-gray-700", "bg-gray-700", "bg-green-600", "bg-green-700", "bg-green-600", "bg-gray-700",
        "bg-gray-700", "bg-gray-700", "bg-gray-800", "bg-gray-700", "bg-gray-700", "bg-green-600", "bg-gray-700", "bg-gray-700"
      ]
    },
    %{
      id: "cloud_city",
      name: "Cloud City",
      emoji: "☁️",
      desc: "Floating platforms above an endless sky",
      difficulty: :medium,
      terrain: %{grass: 0.30, forest: 0.15, water: 0.05, mountain: 0.10, sand: 0.0, desert: 0.40},
      resource_density: :medium,
      danger_level: :normal,
      occupations: [:builder, :trader, :explorer, :healer, :farmer],
      wildlife: [:bird],
      thumb_grid: [
        "bg-sky-300", "bg-sky-200", "bg-sky-300", "bg-sky-200", "bg-sky-300", "bg-sky-200", "bg-sky-300", "bg-sky-200",
        "bg-sky-200", "bg-sky-300", "bg-white", "bg-white", "bg-white", "bg-sky-300", "bg-sky-200", "bg-sky-300",
        "bg-sky-300", "bg-white", "bg-slate-100", "bg-green-400", "bg-slate-100", "bg-white", "bg-sky-300", "bg-sky-200",
        "bg-sky-200", "bg-white", "bg-green-400", "bg-green-500", "bg-green-400", "bg-slate-100", "bg-white", "bg-sky-300",
        "bg-sky-300", "bg-sky-200", "bg-white", "bg-green-400", "bg-slate-100", "bg-white", "bg-sky-200", "bg-sky-300",
        "bg-sky-200", "bg-sky-300", "bg-sky-200", "bg-white", "bg-white", "bg-sky-300", "bg-white", "bg-white",
        "bg-sky-300", "bg-sky-200", "bg-sky-300", "bg-sky-200", "bg-sky-300", "bg-white", "bg-slate-100", "bg-white",
        "bg-sky-200", "bg-sky-300", "bg-sky-200", "bg-sky-300", "bg-sky-200", "bg-sky-300", "bg-white", "bg-sky-300"
      ]
    }
  ]

  @doc "Returns all templates as a list of maps."
  @spec all() :: [template()]
  def all, do: @templates

  @doc "Get a template by id string."
  @spec get(String.t()) :: template() | nil
  def get(id) do
    Enum.find(@templates, fn t -> t.id == id end)
  end

  @doc "Get a template by id string, falling back to village."
  @spec get!(String.t()) :: template()
  def get!(id) do
    get(id) || get("village")
  end

  @doc "Returns the thumbnail grid color at index for a given template id."
  @spec thumb_color(String.t(), non_neg_integer()) :: String.t()
  def thumb_color(id, index) when index >= 0 and index < 64 do
    case get(id) do
      nil -> "bg-green-600"
      t -> Enum.at(t.thumb_grid, index, "bg-green-600")
    end
  end

  def thumb_color(_, _), do: "bg-green-600"

  @doc "Returns the difficulty label with color class."
  @spec difficulty_badge(template()) :: {String.t(), String.t()}
  def difficulty_badge(%{difficulty: :easy}), do: {"Easy", "text-green-400"}
  def difficulty_badge(%{difficulty: :medium}), do: {"Medium", "text-yellow-400"}
  def difficulty_badge(%{difficulty: :hard}), do: {"Hard", "text-orange-400"}
  def difficulty_badge(%{difficulty: :extreme}), do: {"Extreme", "text-red-400"}
end
