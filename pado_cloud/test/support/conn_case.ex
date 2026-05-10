defmodule PadoCloudWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint PadoCloudWeb.Endpoint

      use PadoCloudWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import PadoCloudWeb.ConnCase
    end
  end

  setup tags do
    PadoCloud.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
