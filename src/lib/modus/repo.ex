defmodule Modus.Repo do
  @moduledoc "Modus.Repo — auto-documented by Probatio quality pass."
  use Ecto.Repo,
    otp_app: :modus,
    adapter: Ecto.Adapters.SQLite3
end
