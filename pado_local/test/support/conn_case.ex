defmodule PadoLocalWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint PadoLocalWeb.Endpoint

      use PadoLocalWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import PadoLocalWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
