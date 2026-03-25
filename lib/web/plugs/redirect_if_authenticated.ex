defmodule Web.Plugs.RedirectIfAuthenticated do
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]
  import Web.AccountAuth, only: [authenticated?: 1, signed_in_path: 1]

  def init(opts), do: opts

  def call(conn, _opts) do
    if authenticated?(conn) do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end
end
