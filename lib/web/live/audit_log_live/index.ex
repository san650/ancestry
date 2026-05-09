defmodule Web.AuditLogLive.Index do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Audit.Log,
    scope_subject: &Function.identity/1,
    skip_preload: [:index]

  alias Ancestry.Audit
  alias Web.AuditLogLive.Components
  alias Web.AuditLogLive.Shared

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
    if connected?(socket), do: Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log")

    {:ok,
     socket
     |> assign(:page_title, gettext("Audit log"))
     |> assign(:filters, %{})
     |> assign(:cursor, nil)
     |> assign(:has_more?, false)
     |> assign(:organizations, Ancestry.Organizations.list_organizations())
     |> assign(:accounts, Audit.list_audit_accounts(%{}))
     |> stream(:entries, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)
    rows = Audit.list_entries(filters, @limit)
    accounts = Audit.list_audit_accounts(Map.take(filters, [:organization_id]))

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:accounts, accounts)
     |> assign(:cursor, Shared.cursor_from(rows))
     |> assign(:has_more?, length(rows) == @limit)
     |> stream(:entries, rows, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    pairs =
      params
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    path =
      if pairs == [],
        do: ~p"/admin/audit-log",
        else: ~p"/admin/audit-log?#{pairs}"

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("load_more", _, socket) do
    filters = Map.put(socket.assigns.filters, :before, socket.assigns.cursor)
    rows = Audit.list_entries(filters, @limit)

    socket =
      Enum.reduce(rows, socket, fn row, s -> stream_insert(s, :entries, row, at: -1) end)

    {:noreply,
     socket
     |> assign(:cursor, Shared.cursor_from(rows) || socket.assigns.cursor)
     |> assign(:has_more?, length(rows) == @limit)}
  end

  @impl true
  def handle_info({:audit_logged, row}, socket) do
    if Shared.matches_filters?(row, socket.assigns.filters) do
      {:noreply, stream_insert(socket, :entries, row, at: 0)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6" {test_id("audit-log")}>
        <h1 class="font-cm-display text-cm-indigo text-lg uppercase pb-4">
          {gettext("Audit log")}
        </h1>
        <Components.filter_bar
          organizations={@organizations}
          accounts={@accounts}
          filters={@filters}
        />
        <Components.audit_table stream={@streams.entries} />
        <Components.viewport_sentinel has_more?={@has_more?} />
      </div>
    </Layouts.app>
    """
  end

  defp parse_filters(params) do
    %{}
    |> Shared.maybe_put(:organization_id, Shared.parse_int(params["organization_id"]))
    |> Shared.maybe_put(:account_id, Shared.parse_int(params["account_id"]))
  end
end
