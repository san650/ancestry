defmodule Web.AuditLogLive.Show do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Audit.Log,
    scope_subject: &Function.identity/1,
    skip_preload: [:show]

  alias Ancestry.Audit

  @impl true
  def handle_unauthorized(_action, socket) do
    {:halt,
     socket
     |> put_flash(:error, gettext("You don't have permission to access this page"))
     |> push_navigate(to: ~p"/org")}
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    entry = Audit.get_entry!(id)

    related =
      entry.correlation_id
      |> Audit.list_correlated_entries()
      |> Enum.reject(&(&1.id == entry.id))

    {:ok,
     socket
     |> assign(:page_title, gettext("Audit entry"))
     |> assign(:entry, entry)
     |> assign(:related, related)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-6 space-y-6"
        {test_id("audit-detail")}
      >
        <h1 class="font-cm-display text-cm-indigo text-lg uppercase">
          {gettext("Audit entry")}
        </h1>

        <dl class="grid grid-cols-3 gap-2 font-cm-mono text-[11px]">
          <dt class="font-bold uppercase">{gettext("Timestamp")}</dt>
          <dd class="col-span-2">
            {Calendar.strftime(@entry.inserted_at, "%Y-%m-%d %H:%M:%S")}
          </dd>
          <dt class="font-bold uppercase">{gettext("Account")}</dt>
          <dd class="col-span-2">{@entry.account_email}</dd>
          <dt class="font-bold uppercase">{gettext("Organization")}</dt>
          <dd class="col-span-2">{@entry.organization_name || "—"}</dd>
          <dt class="font-bold uppercase">{gettext("Command")}</dt>
          <dd class="col-span-2">{@entry.command_module}</dd>
          <dt class="font-bold uppercase">command_id</dt>
          <dd class="col-span-2">{@entry.command_id}</dd>
          <dt class="font-bold uppercase">correlation_id</dt>
          <dd class="col-span-2">{@entry.correlation_id}</dd>
          <dt class="font-bold uppercase">{gettext("Payload")}</dt>
          <dd class="col-span-2">
            <pre class="whitespace-pre-wrap break-all">{Jason.encode!(@entry.payload, pretty: true)}</pre>
          </dd>
        </dl>

        <section>
          <h2 class="font-cm-display text-cm-indigo text-base uppercase pb-2">
            {gettext("Related events")}
          </h2>
          <p :if={@related == []}>{gettext("No related events")}</p>
          <ul :if={@related != []} class="space-y-2 font-cm-mono text-[11px]">
            <li :for={r <- @related} {test_id("related-event-#{r.id}")}>
              <.link
                navigate={~p"/admin/audit-log/#{r.id}"}
                class="underline text-cm-coral"
              >
                {Calendar.strftime(r.inserted_at, "%Y-%m-%d %H:%M:%S")} — {short(r.command_module)}
              </.link>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp short(mod), do: mod |> String.split(".") |> List.last()
end
