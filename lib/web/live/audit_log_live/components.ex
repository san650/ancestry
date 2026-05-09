defmodule Web.AuditLogLive.Components do
  @moduledoc "Shared function components for the audit-log LiveViews."
  use Phoenix.Component
  use Gettext, backend: Web.Gettext

  import Web.Helpers.TestHelpers

  attr :id, :string, default: "audit-table"
  attr :stream, :any, required: true
  attr :expanded_id, :any, default: nil

  def audit_table(assigns) do
    ~H"""
    <div id={@id} phx-update="stream" {test_id("audit-table")}>
      <div :for={{dom_id, row} <- @stream} id={dom_id} {test_id("audit-row-#{row.id}")}>
        <button
          type="button"
          phx-click="toggle"
          phx-value-id={row.id}
          class="w-full grid grid-cols-12 gap-2 items-start px-4 py-3 border-b border-cm-border/20 text-left hover:bg-cm-surface"
        >
          <span class="col-span-2 font-cm-mono text-[11px] text-cm-text-muted">
            {Calendar.strftime(row.inserted_at, "%Y-%m-%d %H:%M:%S")}
          </span>
          <span class="col-span-3 font-cm-mono text-[11px]">{row.account_email}</span>
          <span class="col-span-2 font-cm-mono text-[11px]">
            {row.organization_name || "—"}
          </span>
          <span class="col-span-2 font-cm-mono text-[11px] font-bold">
            {short_command(row.command_module)}
          </span>
          <span class="col-span-3 font-cm-mono text-[10px] text-cm-text-muted truncate">
            {payload_preview(row.payload)}
          </span>
        </button>

        <div
          :if={@expanded_id == row.id}
          class="px-4 py-3 bg-cm-surface text-[11px] font-cm-mono"
          {test_id("audit-row-expanded-#{row.id}")}
        >
          <div><strong>command_id:</strong> {row.command_id}</div>
          <div><strong>correlation_id:</strong> {row.correlation_id}</div>
          <pre class="whitespace-pre-wrap break-all">{Jason.encode!(row.payload, pretty: true)}</pre>
          <.link
            navigate={"/admin/audit-log/#{row.id}"}
            class="text-cm-coral underline"
            {test_id("audit-row-open-#{row.id}")}
          >
            {gettext("Open")}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp short_command(mod) when is_binary(mod) do
    mod |> String.split(".") |> List.last()
  end

  defp short_command(_), do: ""

  defp payload_preview(payload) do
    json = Jason.encode!(payload)
    if String.length(json) > 120, do: String.slice(json, 0, 117) <> "...", else: json
  end

  attr :organizations, :list, required: true
  attr :accounts, :list, required: true
  attr :filters, :map, required: true
  attr :show_organization?, :boolean, default: true

  def filter_bar(assigns) do
    ~H"""
    <form
      id="audit-filter"
      phx-change="filter"
      class="flex flex-wrap gap-3 items-end pb-4"
      {test_id("audit-filter")}
    >
      <label :if={@show_organization?} class="flex flex-col text-[11px] font-cm-mono">
        <span class="font-bold uppercase">{gettext("Organization")}</span>
        <select
          name="filters[organization_id]"
          class="border border-cm-border rounded-cm px-2 py-1"
          {test_id("audit-filter-org")}
        >
          <option value="">{gettext("All organizations")}</option>
          <option
            :for={org <- @organizations}
            value={org.id}
            selected={"#{@filters[:organization_id]}" == "#{org.id}"}
          >
            {org.name}
          </option>
        </select>
      </label>

      <label class="flex flex-col text-[11px] font-cm-mono">
        <span class="font-bold uppercase">{gettext("Account")}</span>
        <select
          name="filters[account_id]"
          class="border border-cm-border rounded-cm px-2 py-1"
          {test_id("audit-filter-account")}
        >
          <option value="">{gettext("All accounts")}</option>
          <option
            :for={acc <- @accounts}
            value={acc.id}
            selected={"#{@filters[:account_id]}" == "#{acc.id}"}
          >
            {acc.email}
          </option>
        </select>
      </label>
    </form>
    """
  end

  attr :has_more?, :boolean, required: true

  def viewport_sentinel(assigns) do
    ~H"""
    <div :if={@has_more?} id="audit-load-more-wrapper" class="py-6 text-center">
      <button
        id="audit-load-more"
        type="button"
        phx-click="load_more"
        phx-viewport-bottom="load_more"
        class="font-cm-mono text-[11px] uppercase tracking-wider text-cm-coral underline"
        {test_id("audit-load-more")}
      >
        {gettext("Load more")}
      </button>
    </div>
    """
  end
end
