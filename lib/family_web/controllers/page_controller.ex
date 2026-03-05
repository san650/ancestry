defmodule FamilyWeb.PageController do
  use FamilyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
