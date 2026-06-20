defmodule PadoLocal.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PadoLocalWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:pado_local, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PadoLocal.PubSub},
      PadoLocalWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: PadoLocal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PadoLocalWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
