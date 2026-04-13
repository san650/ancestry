defmodule Ancestry.Permissions do
  @moduledoc "Defines who can do what. Pattern matches on Scope."
  use Permit.Permissions, actions_module: Ancestry.Actions

  alias Ancestry.Identity.{Account, Scope}

  def can(%Scope{account: %Account{role: :admin}}) do
    permit()
    |> all(Account)
  end

  def can(%Scope{account: %Account{role: _}}) do
    permit()
  end

  def can(_), do: permit()
end
