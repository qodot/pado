defmodule PadoWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PadoWebWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:pado_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PadoWeb.PubSub},
      PadoWebWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: PadoWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PadoWebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
