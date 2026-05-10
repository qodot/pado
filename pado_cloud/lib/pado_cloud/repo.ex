defmodule PadoCloud.Repo do
  use Ecto.Repo,
    otp_app: :pado_cloud,
    adapter: Ecto.Adapters.Postgres
end
