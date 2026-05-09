defmodule Ancestry.Permissions do
  @moduledoc "Defines who can do what. Pattern matches on Scope."
  use Permit.Permissions, actions_module: Ancestry.Actions

  alias Ancestry.Comments.PhotoComment
  alias Ancestry.Families.Family
  alias Ancestry.Galleries.{Gallery, Photo}
  alias Ancestry.Identity.{Account, Scope}
  alias Ancestry.Organizations.Organization
  alias Ancestry.People.Person

  def can(%Scope{account: %Account{role: :admin}}) do
    permit()
    |> all(Account)
    |> all(Organization)
    |> all(Family)
    |> all(Person)
    |> all(Gallery)
    |> all(Photo)
    |> all(PhotoComment)
  end

  def can(%Scope{account: %Account{role: :editor, id: id}}) do
    permit()
    |> read(Organization)
    |> all(Family)
    |> all(Person)
    |> all(Gallery)
    |> all(Photo)
    |> read(PhotoComment)
    |> create(PhotoComment)
    |> update(PhotoComment, account_id: id)
    |> delete(PhotoComment, account_id: id)
  end

  def can(%Scope{account: %Account{role: :viewer}}) do
    permit()
    |> read(Organization)
    |> read(Family)
    |> read(Person)
    |> read(Gallery)
    |> read(Photo)
    |> read(PhotoComment)
    |> create(PhotoComment)
  end

  def can(_), do: permit()
end
