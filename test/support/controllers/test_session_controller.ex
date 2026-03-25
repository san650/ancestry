defmodule Web.TestSessionController do
  @moduledoc false
  use Web, :controller

  def create(conn, %{"account_id" => account_id}) do
    account = Ancestry.Identity.get_account!(String.to_integer(account_id))
    Web.AccountAuth.log_in_account(conn, account, %{"remember_me" => "true"})
  end
end
