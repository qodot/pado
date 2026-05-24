defmodule PadoWebWeb.Router do
  use PadoWebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PadoWebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PadoWebWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/sessions", SessionLive, :index
    live "/sessions/:id", SessionLive, :show
  end

  if Application.compile_env(:pado_web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PadoWebWeb.Telemetry
    end
  end
end
