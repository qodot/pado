defmodule PadoLocalWeb.PageController do
  use PadoLocalWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
