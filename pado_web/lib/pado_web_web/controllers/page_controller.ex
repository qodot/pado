defmodule PadoWebWeb.PageController do
  use PadoWebWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
