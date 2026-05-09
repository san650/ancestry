defmodule Web.AuditLogLive.OrgIndex do
  use Web, :live_view

  alias Ancestry.Audit
  alias Web.AuditLogLive.Components

  @limit 50

  @impl true
  def mount(_params, _session, socket) do
    if Ancestry.Authorization.can?(socket.assigns.current_scope, :index, Ancestry.Audit.Log) do
      org_id = socket.assigns.current_scope.organization.id

      if connected?(socket),
        do: Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log:org:#{org_id}")

      {:ok,
       socket
       |> assign(:page_title, gettext("Audit log"))
       |> assign(:filters, %{organization_id: org_id})
       |> assign(:cursor, nil)
       |> assign(:has_more?, false)
       |> assign(:accounts, Audit.list_audit_accounts(%{organization_id: org_id}))
       |> stream(:entries, [])}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("You don't have permission to access this page"))
       |> push_navigate(to: ~p"/org")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    org_id = socket.assigns.current_scope.organization.id

    filters =
      %{organization_id: org_id}
      |> maybe_put(:account_id, parse_int(params["account_id"]))

    rows = Audit.list_entries(filters, @limit)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:cursor, cursor_from(rows))
     |> assign(:has_more?, length(rows) == @limit)
     |> stream(:entries, rows, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    org_id = socket.assigns.current_scope.organization.id

    pairs =
      params
      |> Map.take(["account_id"])
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)

    path =
      if pairs == [],
        do: ~p"/org/#{org_id}/audit-log",
        else: ~p"/org/#{org_id}/audit-log?#{pairs}"

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("load_more", _, socket) do
    filters = Map.put(socket.assigns.filters, :before, socket.assigns.cursor)
    rows = Audit.list_entries(filters, @limit)

    socket =
      Enum.reduce(rows, socket, fn row, s -> stream_insert(s, :entries, row, at: -1) end)

    {:noreply,
     socket
     |> assign(:cursor, cursor_from(rows) || socket.assigns.cursor)
     |> assign(:has_more?, length(rows) == @limit)}
  end

  @impl true
  def handle_info({:audit_logged, row}, socket) do
    if matches_filters?(row, socket.assigns.filters) do
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
          organizations={[]}
          accounts={@accounts}
          filters={@filters}
          show_organization?={false}
        />
        <Components.audit_table stream={@streams.entries} />
        <Components.viewport_sentinel has_more?={@has_more?} />
      </div>
    </Layouts.app>
    """
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(s) when is_binary(s), do: String.to_integer(s)

  defp cursor_from([]), do: nil
  defp cursor_from(rows), do: rows |> List.last() |> then(&{&1.inserted_at, &1.id})

  defp matches_filters?(row, filters) do
    Enum.all?(filters, fn
      {:organization_id, id} -> row.organization_id == id
      {:account_id, id} -> row.account_id == id
      {:before, _} -> true
    end)
  end
end
