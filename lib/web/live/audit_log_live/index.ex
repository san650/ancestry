defmodule Web.AuditLogLive.Index do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Audit.Log,
    scope_subject: &Function.identity/1,
    skip_preload: [:index]

  alias Ancestry.Audit
  alias Web.AuditLogLive.Components

  @limit 50

  @impl true
  def handle_unauthorized(_action, socket) do
    {:halt,
     socket
     |> put_flash(:error, gettext("You don't have permission to access this page"))
     |> push_navigate(to: ~p"/org")}
  end

  @impl true
  def mount(_params, _session, socket) do
    rows = Audit.list_entries(%{}, @limit)

    {:ok,
     socket
     |> assign(:page_title, gettext("Audit log"))
     |> assign(:expanded_id, nil)
     |> stream(:entries, rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6" {test_id("audit-log")}>
        <h1 class="font-cm-display text-cm-indigo text-lg uppercase pb-4">
          {gettext("Audit log")}
        </h1>
        <Components.audit_table stream={@streams.entries} expanded_id={@expanded_id} />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    id = String.to_integer(id)
    next = if socket.assigns.expanded_id == id, do: nil, else: id
    {:noreply, assign(socket, :expanded_id, next)}
  end
end
