defmodule PadoWebWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint PadoWebWeb.Endpoint

      use PadoWebWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import PadoWebWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
