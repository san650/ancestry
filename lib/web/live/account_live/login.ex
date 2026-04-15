defmodule Web.AccountLive.Login do
  use Web, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex flex-col items-center justify-center min-h-[80svh] px-6">
        <div class="w-full max-w-sm">
          <%!-- Logo --%>
          <div class="flex flex-col items-center pt-16 pb-8 lg:pt-8">
            <h1 class="font-ds-heading text-lg font-bold text-ds-on-surface">{gettext("Log in")}</h1>
            <p
              :if={@current_scope}
              class="mt-2 text-sm font-ds-body text-ds-on-surface-variant text-center"
            >
              {gettext("You need to reauthenticate to perform sensitive actions on your account.")}
            </p>
          </div>

          <.form
            :let={f}
            for={@form}
            id="login_form_password"
            action={~p"/accounts/log-in"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
          >
            <div class="flex flex-col gap-4">
              <.input
                readonly={!!@current_scope}
                field={f[:email]}
                type="email"
                label={gettext("Email")}
                autocomplete="username"
                spellcheck="false"
                required
                class="w-full px-4 py-3 bg-ds-surface-card border border-ds-outline-variant/20 rounded-ds-sharp text-base font-ds-body text-ds-on-surface placeholder:text-ds-on-surface-variant/50 focus:border-ds-primary focus:ring-1 focus:ring-ds-primary"
              />
              <.input
                field={@form[:password]}
                type="password"
                label={gettext("Password")}
                autocomplete="current-password"
                spellcheck="false"
                class="w-full px-4 py-3 bg-ds-surface-card border border-ds-outline-variant/20 rounded-ds-sharp text-base font-ds-body text-ds-on-surface placeholder:text-ds-on-surface-variant/50 focus:border-ds-primary focus:ring-1 focus:ring-ds-primary"
              />

              <button
                type="submit"
                name={@form[:remember_me].name}
                value="true"
                class="w-full py-3 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary font-ds-heading font-bold text-sm rounded-ds-sharp transition-all hover:brightness-110 focus:ring-2 focus:ring-ds-primary focus:ring-offset-2 cursor-pointer"
              >
                {gettext("Log in and stay logged in")}
              </button>
              <button
                type="submit"
                class="w-full py-3 bg-ds-surface-high text-ds-on-surface text-sm font-ds-body font-semibold rounded-ds-sharp transition-colors hover:bg-ds-surface-highest cursor-pointer"
              >
                {gettext("Log in only this time")}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:account), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "account")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
