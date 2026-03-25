defmodule Web.PageController do
  use Web, :controller

  def landing(conn, _args) do
    render(conn, :landing, [])
  end
end
