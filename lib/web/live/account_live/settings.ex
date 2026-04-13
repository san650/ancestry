defmodule Web.AccountLive.Settings do
  use Web, :live_view

  alias Ancestry.Identity

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex items-start justify-center min-h-[70vh] px-4 pt-12">
        <div class="w-full max-w-md space-y-8">
          <div class="text-center">
            <h1 class="font-ds-heading text-lg font-bold text-ds-on-surface">
              {gettext("Account Settings")}
            </h1>
            <p class="mt-2 text-sm font-ds-body text-ds-on-surface-variant">
              {gettext("Manage your account email address and password settings")}
            </p>
          </div>

          <div class="bg-ds-surface-card rounded-ds-sharp p-6 shadow-ds-ambient">
            <h2 class="font-ds-heading text-lg font-bold text-ds-on-surface mb-4">
              {gettext("Email")}
            </h2>
            <.form
              for={@email_form}
              id="email_form"
              phx-submit="update_email"
              phx-change="validate_email"
            >
              <.input
                field={@email_form[:email]}
                type="email"
                label={gettext("Email")}
                autocomplete="username"
                spellcheck="false"
                required
              />
              <button
                type="submit"
                phx-disable-with={gettext("Changing...")}
                class="mt-4 px-6 py-2.5 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary text-sm font-ds-body font-semibold rounded-ds-sharp transition-opacity hover:opacity-90 cursor-pointer"
              >
                {gettext("Change Email")}
              </button>
            </.form>
          </div>

          <div class="bg-ds-surface-card rounded-ds-sharp p-6 shadow-ds-ambient">
            <h2 class="font-ds-heading text-lg font-bold text-ds-on-surface mb-4">
              {gettext("Password")}
            </h2>
            <.form
              for={@password_form}
              id="password_form"
              action={~p"/accounts/update-password"}
              method="post"
              phx-change="validate_password"
              phx-submit="update_password"
              phx-trigger-action={@trigger_submit}
            >
              <input
                name={@password_form[:email].name}
                type="hidden"
                id="hidden_account_email"
                spellcheck="false"
                value={@current_email}
              />
              <.input
                field={@password_form[:password]}
                type="password"
                label={gettext("New password")}
                autocomplete="new-password"
                spellcheck="false"
                required
              />
              <.input
                field={@password_form[:password_confirmation]}
                type="password"
                label={gettext("Confirm new password")}
                autocomplete="new-password"
                spellcheck="false"
              />
              <button
                type="submit"
                phx-disable-with={gettext("Saving...")}
                class="mt-4 px-6 py-2.5 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary text-sm font-ds-body font-semibold rounded-ds-sharp transition-opacity hover:opacity-90 cursor-pointer"
              >
                {gettext("Save Password")}
              </button>
            </.form>
          </div>

          <div class="bg-ds-surface-card rounded-ds-sharp p-6 shadow-ds-ambient">
            <h2 class="font-ds-heading text-lg font-bold text-ds-on-surface mb-4">
              {gettext("Language")}
            </h2>
            <.form
              for={@locale_form}
              id="locale_form"
              phx-submit="update_locale"
              phx-change="validate_locale"
            >
              <.input
                field={@locale_form[:locale]}
                type="select"
                label={gettext("Language")}
                options={[{"English", "en-US"}, {"Español", "es-UY"}]}
              />
              <button
                type="submit"
                phx-disable-with={gettext("Saving...")}
                class="mt-4 px-6 py-2.5 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary text-sm font-ds-body font-semibold rounded-ds-sharp transition-opacity hover:opacity-90 cursor-pointer"
              >
                {gettext("Save Language")}
              </button>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Identity.update_account_email(socket.assigns.current_scope.account, token) do
        {:ok, _account} ->
          put_flash(socket, :info, gettext("Email changed successfully."))

        {:error, _} ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/accounts/settings")}
  end

  def mount(_params, _session, socket) do
    account = socket.assigns.current_scope.account
    email_changeset = Identity.change_account_email(account, %{}, validate_unique: false)
    password_changeset = Identity.change_account_password(account, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, account.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:locale_form, to_form(Identity.change_account_locale(account)))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"account" => account_params} = params

    email_form =
      socket.assigns.current_scope.account
      |> Identity.change_account_email(account_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"account" => account_params} = params
    account = socket.assigns.current_scope.account

    case Identity.change_account_email(account, account_params) do
      %{valid?: true} = changeset ->
        Identity.deliver_account_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          account.email,
          &url(~p"/accounts/settings/confirm-email/#{&1}")
        )

        info = gettext("A link to confirm your email change has been sent to the new address.")
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"account" => account_params} = params

    password_form =
      socket.assigns.current_scope.account
      |> Identity.change_account_password(account_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"account" => account_params} = params
    account = socket.assigns.current_scope.account

    case Identity.change_account_password(account, account_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_locale", %{"account" => locale_params}, socket) do
    locale_form =
      socket.assigns.current_scope.account
      |> Identity.change_account_locale(locale_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, locale_form: locale_form)}
  end

  def handle_event("update_locale", %{"account" => locale_params}, socket) do
    account = socket.assigns.current_scope.account

    case Identity.update_account_locale(account, locale_params) do
      {:ok, updated_account} ->
        Gettext.put_locale(Web.Gettext, updated_account.locale)
        scope = %{socket.assigns.current_scope | account: updated_account}

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign(:locale_form, to_form(Identity.change_account_locale(updated_account)))
         |> put_flash(:info, gettext("Language updated successfully."))}

      {:error, changeset} ->
        {:noreply, assign(socket, locale_form: to_form(changeset, action: :insert))}
    end
  end
end
