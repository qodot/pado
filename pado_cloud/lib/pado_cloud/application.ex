defmodule PadoCloud.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PadoCloudWeb.Telemetry,
      PadoCloud.Repo,
      {DNSCluster, query: Application.get_env(:pado_cloud, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PadoCloud.PubSub},
      PadoCloudWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: PadoCloud.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PadoCloudWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
