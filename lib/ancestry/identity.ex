defmodule Ancestry.Identity do
  @moduledoc """
  The Identity context.
  """

  import Ecto.Query, warn: false
  alias Ancestry.Repo

  alias Ancestry.Identity.{Account, AccountToken, AccountNotifier}

  ## Database getters

  @doc """
  Gets a account by email.

  ## Examples

      iex> get_account_by_email("foo@example.com")
      %Account{}

      iex> get_account_by_email("unknown@example.com")
      nil

  """
  def get_account_by_email(email) when is_binary(email) do
    Repo.get_by(Account, email: email)
  end

  @doc """
  Gets a account by email and password.

  ## Examples

      iex> get_account_by_email_and_password("foo@example.com", "correct_password")
      %Account{}

      iex> get_account_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_account_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    account = Repo.get_by(Account, email: email)

    cond do
      !Account.valid_password?(account, password) -> nil
      account.deactivated_at != nil -> nil
      true -> account
    end
  end

  @doc """
  Gets a single account.

  Raises `Ecto.NoResultsError` if the Account does not exist.

  ## Examples

      iex> get_account!(123)
      %Account{}

      iex> get_account!(456)
      ** (Ecto.NoResultsError)

  """
  def get_account!(id), do: Repo.get!(Account, id)

  ## Account registration

  @doc """
  Registers a account.

  ## Examples

      iex> register_account(%{field: value})
      {:ok, %Account{}}

      iex> register_account(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_account(attrs) do
    %Account{}
    |> Account.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the account is in sudo mode.

  The account is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(account, minutes \\ -20)

  def sudo_mode?(%Account{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_account, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the account email.

  See `Ancestry.Identity.Account.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_account_email(account)
      %Ecto.Changeset{data: %Account{}}

  """
  def change_account_email(account, attrs \\ %{}, opts \\ []) do
    Account.email_changeset(account, attrs, opts)
  end

  @doc """
  Updates the account email using the given token.

  If the token matches, the account email is updated and the token is deleted.
  """
  def update_account_email(account, token) do
    context = "change:#{account.email}"

    Repo.transact(fn ->
      with {:ok, query} <- AccountToken.verify_change_email_token_query(token, context),
           %AccountToken{sent_to: email} <- Repo.one(query),
           {:ok, account} <- Repo.update(Account.email_changeset(account, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(
               from(AccountToken, where: [account_id: ^account.id, context: ^context])
             ) do
        {:ok, account}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the account password.

  See `Ancestry.Identity.Account.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_account_password(account)
      %Ecto.Changeset{data: %Account{}}

  """
  def change_account_password(account, attrs \\ %{}, opts \\ []) do
    Account.password_changeset(account, attrs, opts)
  end

  @doc """
  Updates the account password.

  Returns a tuple with the updated account, as well as a list of expired tokens.

  ## Examples

      iex> update_account_password(account, %{password: ...})
      {:ok, {%Account{}, [...]}}

      iex> update_account_password(account, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_account_password(account, attrs) do
    account
    |> Account.password_changeset(attrs)
    |> update_account_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_account_session_token(account) do
    {token, account_token} = AccountToken.build_session_token(account)
    Repo.insert!(account_token)
    token
  end

  @doc """
  Gets the account with the given signed token.

  If the token is valid `{account, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_account_by_session_token(token) do
    {:ok, query} = AccountToken.verify_session_token_query(token)

    case Repo.one(query) do
      {%Account{deactivated_at: deactivated_at}, _token_inserted_at}
      when not is_nil(deactivated_at) ->
        nil

      result ->
        result
    end
  end

  @doc """
  Gets the account with the given magic link token.
  """
  def get_account_by_magic_link_token(token) do
    with {:ok, query} <- AccountToken.verify_magic_link_token_query(token),
         {%Account{deactivated_at: nil} = account, _token} <- Repo.one(query) do
      account
    else
      _ -> nil
    end
  end

  @doc """
  Logs the account in by magic link.

  There are three cases to consider:

  1. The account has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The account has not confirmed their email and no password is set.
     In this case, the account gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The account has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_account_by_magic_link(token) do
    {:ok, query} = AccountToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent deactivated accounts from logging in
      {%Account{deactivated_at: deactivated_at}, _token} when not is_nil(deactivated_at) ->
        {:error, :not_found}

      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%Account{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%Account{confirmed_at: nil} = account, _token} ->
        account
        |> Account.confirm_changeset()
        |> update_account_and_delete_all_tokens()

      {account, token} ->
        Repo.delete!(token)
        {:ok, {account, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given account.

  ## Examples

      iex> deliver_account_update_email_instructions(account, current_email, &url(~p"/accounts/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_account_update_email_instructions(
        %Account{} = account,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, account_token} =
      AccountToken.build_email_token(account, "change:#{current_email}")

    Repo.insert!(account_token)

    AccountNotifier.deliver_update_email_instructions(
      account,
      update_email_url_fun.(encoded_token)
    )
  end

  @doc """
  Delivers the magic link login instructions to the given account.
  """
  def deliver_login_instructions(
        %Account{deactivated_at: deactivated_at} = _account,
        _magic_link_url_fun
      )
      when not is_nil(deactivated_at) do
    {:ok, :deactivated}
  end

  def deliver_login_instructions(%Account{} = account, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, account_token} = AccountToken.build_email_token(account, "login")
    Repo.insert!(account_token)
    AccountNotifier.deliver_login_instructions(account, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_account_session_token(token) do
    Repo.delete_all(from(AccountToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Admin account management

  alias Ecto.Multi
  alias Ancestry.Organizations.AccountOrganization

  @doc """
  Lists all accounts sorted by email, with organizations preloaded.
  """
  def list_accounts do
    from(Account, order_by: [asc: :email], preload: :organizations)
    |> Repo.all()
  end

  @doc """
  Gets a single account with organizations and deactivator preloaded.

  Raises `Ecto.NoResultsError` if the Account does not exist.
  """
  def get_account_with_orgs!(id) do
    Repo.get!(Account, id) |> Repo.preload([:organizations, :deactivator])
  end

  @doc """
  Creates an account via admin, using `Account.admin_changeset/3`.

  Inserts `AccountOrganization` records for each `org_id` in the list.
  """
  def create_admin_account(attrs, org_ids) do
    multi =
      Multi.new()
      |> Multi.insert(:account, Account.admin_changeset(%Account{}, attrs))
      |> Multi.run(:account_organizations, fn repo, %{account: account} ->
        account_orgs =
          Enum.map(org_ids, fn org_id ->
            %AccountOrganization{}
            |> AccountOrganization.changeset(%{account_id: account.id, organization_id: org_id})
            |> repo.insert!()
          end)

        {:ok, account_orgs}
      end)

    case Repo.transaction(multi) do
      {:ok, %{account: account}} -> {:ok, account}
      {:error, :account, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Updates an account via admin, using `Account.admin_changeset/3` with `mode: :edit`.

  Prevents an admin from changing their own role. The `performer` is the admin
  performing the action.
  """
  def update_admin_account(account, attrs, performer) do
    new_role = attrs[:role] || attrs["role"]

    if account.id == performer.id && new_role && to_string(new_role) != to_string(account.role) do
      {:error, :cannot_change_own_role}
    else
      Account.admin_changeset(account, attrs, mode: :edit)
      |> Repo.update()
    end
  end

  @doc """
  Replaces the organization associations for an account.

  Deletes all existing `AccountOrganization` records and inserts new ones.
  """
  def update_account_organizations(account, org_ids) do
    multi =
      Multi.new()
      |> Multi.delete_all(
        :delete_orgs,
        from(ao in AccountOrganization, where: ao.account_id == ^account.id)
      )
      |> Multi.run(:insert_orgs, fn repo, _changes ->
        account_orgs =
          Enum.map(org_ids, fn org_id ->
            %AccountOrganization{}
            |> AccountOrganization.changeset(%{account_id: account.id, organization_id: org_id})
            |> repo.insert!()
          end)

        {:ok, account_orgs}
      end)

    case Repo.transaction(multi) do
      {:ok, _} -> :ok
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Deactivates an account, deleting all its tokens and disconnecting sessions.

  Returns `{:error, :cannot_deactivate_self}` if target == performer.
  Returns `{:error, :last_admin}` if the target is an admin and deactivation
  would leave zero active admins.
  """
  def deactivate_account(%Account{} = target, %Account{} = performer) do
    if target.id == performer.id do
      {:error, :cannot_deactivate_self}
    else
      do_deactivate_account(target, performer)
    end
  end

  defp do_deactivate_account(target, performer) do
    now = DateTime.utc_now(:second)

    multi =
      Multi.new()
      |> Multi.run(:last_admin_check, fn repo, _changes ->
        if target.role == :admin do
          active_admins =
            repo.all(
              from(a in Account,
                where: a.role == :admin,
                where: is_nil(a.deactivated_at),
                lock: "FOR UPDATE",
                select: a.id
              )
            )

          if length(active_admins) <= 1 do
            {:error, :last_admin}
          else
            {:ok, length(active_admins)}
          end
        else
          {:ok, :not_admin}
        end
      end)
      |> Multi.run(:fetch_tokens, fn repo, _changes ->
        tokens = repo.all(from(t in AccountToken, where: t.account_id == ^target.id))
        {:ok, tokens}
      end)
      |> Multi.run(:deactivate, fn repo, _changes ->
        target
        |> Ecto.Changeset.change(deactivated_at: now, deactivated_by: performer.id)
        |> repo.update()
      end)
      |> Multi.delete_all(
        :delete_tokens,
        from(t in AccountToken, where: t.account_id == ^target.id)
      )

    case Repo.transaction(multi) do
      {:ok, %{deactivate: account, fetch_tokens: tokens}} ->
        Web.AccountAuth.disconnect_sessions(tokens)
        {:ok, account}

      {:error, :last_admin_check, :last_admin, _} ->
        {:error, :last_admin}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  @doc """
  Reactivates a previously deactivated account.
  """
  def reactivate_account(%Account{} = account) do
    account
    |> Ecto.Changeset.change(deactivated_at: nil, deactivated_by: nil)
    |> Repo.update()
  end

  ## Avatar helpers

  @doc "Updates avatar status to processed with the filename."
  def update_avatar_processed(account, filename) do
    account
    |> Ecto.Changeset.change(avatar: filename, avatar_status: "processed")
    |> Repo.update()
  end

  @doc "Updates avatar status."
  def update_avatar_status(account, status) do
    account
    |> Ecto.Changeset.change(avatar_status: status)
    |> Repo.update()
  end

  ## Token helper

  defp update_account_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, account} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(AccountToken, account_id: account.id)

        Repo.delete_all(
          from(t in AccountToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id))
        )

        {:ok, {account, tokens_to_expire}}
      end
    end)
  end
end
