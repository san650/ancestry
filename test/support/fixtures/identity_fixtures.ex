defmodule Ancestry.IdentityFixtures do
  @moduledoc """
  Test helpers for the `Ancestry.Identity` context.

  For creating account records, use the ExMachina factories
  `insert(:account)` and `insert(:unconfirmed_account)` from `Ancestry.Factory`.
  """

  import Ecto.Query

  alias Ancestry.Identity

  def unique_account_email, do: "account#{System.unique_integer()}@example.com"
  def valid_account_password, do: "hello world!"

  def set_password(account) do
    {:ok, {account, _expired_tokens}} =
      Identity.update_account_password(account, %{password: valid_account_password()})

    account
  end

  def extract_account_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Ancestry.Repo.update_all(
      from(t in Identity.AccountToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_account_magic_link_token(account) do
    {encoded_token, account_token} = Identity.AccountToken.build_email_token(account, "login")
    Ancestry.Repo.insert!(account_token)
    {encoded_token, account_token.token}
  end

  def offset_account_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Ancestry.Repo.update_all(
      from(ut in Identity.AccountToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
