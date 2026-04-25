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
            <h1 class="font-cm-display text-lg font-bold text-cm-black">{gettext("Log in")}</h1>
            <p
              :if={@current_scope}
              class="mt-2 text-sm font-cm-body text-cm-text-muted text-center"
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
                class="w-full px-4 py-3 bg-cm-white border border-cm-border/20 rounded-cm text-base font-cm-body text-cm-black placeholder:text-cm-text-muted/50 focus:border-cm-indigo focus:ring-1 focus:ring-cm-indigo"
              />
              <.input
                field={@form[:password]}
                type="password"
                label={gettext("Password")}
                autocomplete="current-password"
                spellcheck="false"
                class="w-full px-4 py-3 bg-cm-white border border-cm-border/20 rounded-cm text-base font-cm-body text-cm-black placeholder:text-cm-text-muted/50 focus:border-cm-indigo focus:ring-1 focus:ring-cm-indigo"
              />

              <button
                type="submit"
                name={@form[:remember_me].name}
                value="true"
                class="w-full py-3 bg-gradient-to-b from-cm-indigo to-cm-indigo text-cm-white font-cm-display font-bold text-sm rounded-cm transition-all hover:brightness-110 focus:ring-2 focus:ring-cm-indigo focus:ring-offset-2 cursor-pointer"
              >
                {gettext("Log in and stay logged in")}
              </button>
              <button
                type="submit"
                class="w-full py-3 bg-cm-surface text-cm-black text-sm font-cm-body font-semibold rounded-cm transition-colors hover:bg-cm-surface cursor-pointer"
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
