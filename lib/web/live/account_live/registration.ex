defmodule Web.AccountLive.Registration do
  use Web, :live_view

  alias Ancestry.Identity
  alias Ancestry.Identity.Account

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex items-center justify-center min-h-[70vh] px-4">
        <div class="w-full max-w-sm space-y-6">
          <div class="text-center">
            <h1 class="font-cm-display text-2xl text-cm-indigo uppercase tracking-wider">
              {gettext("Register")}
            </h1>
            <p class="mt-2 text-sm font-cm-body text-cm-text-muted">
              {gettext("Already registered?")}
              <.link
                navigate={~p"/accounts/log-in"}
                class="font-cm-mono text-[10px] font-bold uppercase tracking-wider text-cm-indigo hover:text-cm-coral"
              >
                {gettext("Log in")}
              </.link>
            </p>
          </div>

          <div class="cm-card p-6">
            <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
              <.input
                field={@form[:email]}
                type="email"
                label={gettext("Email")}
                autocomplete="username"
                spellcheck="false"
                required
                phx-mounted={JS.focus()}
              />

              <button
                type="submit"
                phx-disable-with={gettext("Creating account...")}
                class="w-full mt-4 py-3 bg-cm-indigo text-cm-white font-cm-mono text-[10px] font-bold uppercase tracking-wider rounded-cm transition-colors hover:bg-cm-indigo-hover cursor-pointer"
              >
                {gettext("Create an account")}
              </button>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{account: account}}} = socket)
      when not is_nil(account) do
    {:ok, redirect(socket, to: Web.AccountAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Identity.change_account_email(%Account{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"account" => account_params}, socket) do
    case Identity.register_account(account_params) do
      {:ok, account} ->
        {:ok, _} =
          Identity.deliver_login_instructions(
            account,
            &url(~p"/accounts/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("An email was sent to %{email}, please access it to confirm your account.",
             email: account.email
           )
         )
         |> push_navigate(to: ~p"/accounts/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"account" => account_params}, socket) do
    changeset = Identity.change_account_email(%Account{}, account_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "account")
    assign(socket, form: form)
  end
end
