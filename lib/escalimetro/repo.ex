defmodule Escalimetro.Repo do
  use Ecto.Repo,
    otp_app: :escalimetro,
    adapter: Ecto.Adapters.Postgres
end
