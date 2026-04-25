defmodule Web.AccountLive.Confirmation do
  use Web, :live_view

  alias Ancestry.Identity

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex items-center justify-center min-h-[70vh] px-4">
        <div class="w-full max-w-sm bg-cm-white rounded-cm p-8 space-y-6">
          <div class="text-center">
            <h1 class="font-cm-display text-lg font-bold text-cm-black">
              {gettext("Welcome %{email}", email: @account.email)}
            </h1>
          </div>

          <.form
            :if={!@account.confirmed_at}
            for={@form}
            id="confirmation_form"
            phx-mounted={JS.focus_first()}
            phx-submit="submit"
            action={~p"/accounts/log-in?_action=confirmed"}
            phx-trigger-action={@trigger_submit}
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <button
              type="submit"
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with={gettext("Confirming...")}
              class="w-full py-2.5 bg-gradient-to-b from-cm-indigo to-cm-indigo text-cm-white text-sm font-cm-body font-semibold rounded-cm transition-opacity hover:opacity-90 cursor-pointer"
            >
              {gettext("Confirm and stay logged in")}
            </button>
            <button
              type="submit"
              phx-disable-with={gettext("Confirming...")}
              class="w-full mt-2 py-2.5 bg-cm-surface text-cm-black text-sm font-cm-body font-semibold rounded-cm transition-colors hover:bg-cm-surface cursor-pointer"
            >
              {gettext("Confirm and log in only this time")}
            </button>
          </.form>

          <.form
            :if={@account.confirmed_at}
            for={@form}
            id="login_form"
            phx-submit="submit"
            phx-mounted={JS.focus_first()}
            action={~p"/accounts/log-in"}
            phx-trigger-action={@trigger_submit}
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <%= if @current_scope do %>
              <button
                type="submit"
                phx-disable-with={gettext("Logging in...")}
                class="w-full py-2.5 bg-gradient-to-b from-cm-indigo to-cm-indigo text-cm-white text-sm font-cm-body font-semibold rounded-cm transition-opacity hover:opacity-90 cursor-pointer"
              >
                {gettext("Log in")}
              </button>
            <% else %>
              <button
                type="submit"
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with={gettext("Logging in...")}
                class="w-full py-2.5 bg-gradient-to-b from-cm-indigo to-cm-indigo text-cm-white text-sm font-cm-body font-semibold rounded-cm transition-opacity hover:opacity-90 cursor-pointer"
              >
                {gettext("Keep me logged in on this device")}
              </button>
              <button
                type="submit"
                phx-disable-with={gettext("Logging in...")}
                class="w-full mt-2 py-2.5 bg-cm-surface text-cm-black text-sm font-cm-body font-semibold rounded-cm transition-colors hover:bg-cm-surface cursor-pointer"
              >
                {gettext("Log me in only this time")}
              </button>
            <% end %>
          </.form>

          <p
            :if={!@account.confirmed_at}
            class="bg-cm-surface rounded-cm p-4 text-sm font-cm-body text-cm-text-muted"
          >
            {gettext("Tip: If you prefer passwords, you can enable them in the account settings.")}
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if account = Identity.get_account_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "account")

      {:ok, assign(socket, account: account, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Magic link is invalid or it has expired."))
       |> push_navigate(to: ~p"/accounts/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"account" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "account"), trigger_submit: true)}
  end
end
