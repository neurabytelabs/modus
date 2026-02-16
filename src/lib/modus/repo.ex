defmodule Modus.Repo do
  use Ecto.Repo,
    otp_app: :modus,
    adapter: Ecto.Adapters.SQLite3
end
