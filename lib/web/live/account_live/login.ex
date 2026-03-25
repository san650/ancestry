defmodule Web.AccountLive.Login do
  use Web, :live_view

  alias Ancestry.Identity

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex items-center justify-center min-h-[70vh] px-4">
        <div class="w-full max-w-sm bg-ds-surface-card rounded-ds-sharp p-8 shadow-ds-ambient space-y-6">
          <div class="text-center">
            <h1 class="font-ds-heading text-2xl font-bold text-ds-on-surface">Log in</h1>
            <p :if={@current_scope} class="mt-2 text-sm font-ds-body text-ds-on-surface-variant">
              You need to reauthenticate to perform sensitive actions on your account.
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
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
              spellcheck="false"
            />
            <button
              type="submit"
              name={@form[:remember_me].name}
              value="true"
              class="w-full mt-4 py-2.5 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary text-sm font-ds-body font-semibold rounded-ds-sharp transition-opacity hover:opacity-90 cursor-pointer"
            >
              Log in and stay logged in <span aria-hidden="true">&rarr;</span>
            </button>
            <button
              type="submit"
              class="w-full mt-2 py-2.5 bg-ds-surface-high text-ds-on-surface text-sm font-ds-body font-semibold rounded-ds-sharp transition-colors hover:bg-ds-surface-highest cursor-pointer"
            >
              Log in only this time
            </button>
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
