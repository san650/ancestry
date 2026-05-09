defmodule Web.AuditLogLive.Index do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Audit.Log,
    scope_subject: &Function.identity/1,
    skip_preload: [:index]

  @impl true
  def handle_unauthorized(_action, socket) do
    {:halt,
     socket
     |> put_flash(:error, gettext("You don't have permission to access this page"))
     |> push_navigate(to: ~p"/org")}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Audit log"))
     |> stream(:entries, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6" {test_id("audit-log")}>
        <h1 class="font-cm-display text-cm-indigo text-lg uppercase">
          {gettext("Audit log")}
        </h1>
      </div>
    </Layouts.app>
    """
  end
end
