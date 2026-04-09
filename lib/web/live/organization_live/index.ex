defmodule Web.OrganizationLive.Index do
  use Web, :live_view

  alias Ancestry.Organizations
  alias Ancestry.Organizations.Organization

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete, false)
     |> stream(:organizations, Organizations.list_organizations())
     |> assign(:show_create_modal, false)
     |> assign(:form, to_form(Organizations.change_organization(%Organization{})))}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("new_organization", _, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:form, to_form(Organizations.change_organization(%Organization{})))}
  end

  def handle_event("cancel_create", _, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, false)
     |> assign(:form, to_form(Organizations.change_organization(%Organization{})))}
  end

  def handle_event("validate", %{"organization" => params}, socket) do
    changeset =
      %Organization{}
      |> Organizations.change_organization(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"organization" => params}, socket) do
    case Organizations.create_organization(params) do
      {:ok, organization} ->
        {:noreply,
         socket
         |> stream_insert(:organizations, organization)
         |> assign(:show_create_modal, false)
         |> assign(:form, to_form(Organizations.change_organization(%Organization{})))
         |> put_flash(:info, "Organization created")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_select_mode", _, socket) do
    {:noreply,
     socket
     |> assign(:selection_mode, !socket.assigns.selection_mode)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete, false)
     |> stream(:organizations, Organizations.list_organizations(), reset: true)}
  end

  def handle_event("card_clicked", %{"id" => id}, socket) do
    org_id = String.to_integer(id)

    if socket.assigns.selection_mode do
      selected =
        if MapSet.member?(socket.assigns.selected_ids, org_id),
          do: MapSet.delete(socket.assigns.selected_ids, org_id),
          else: MapSet.put(socket.assigns.selected_ids, org_id)

      org = Organizations.get_organization!(org_id)

      {:noreply,
       socket
       |> assign(:selected_ids, selected)
       |> stream_insert(:organizations, org)}
    else
      {:noreply, push_navigate(socket, to: ~p"/org/#{org_id}")}
    end
  end

  def handle_event("request_batch_delete", _, socket) do
    if MapSet.size(socket.assigns.selected_ids) > 0 do
      {:noreply, assign(socket, :confirm_delete, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_batch_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_batch_delete", _, socket) do
    selected = MapSet.to_list(socket.assigns.selected_ids)

    results =
      Enum.map(selected, fn id ->
        try do
          org = Organizations.get_organization!(id)
          Organizations.delete_organization(org)
        rescue
          Ecto.NoResultsError -> {:error, :not_found}
        end
      end)

    ok_count = Enum.count(results, &match?({:ok, _}, &1))
    error_count = length(results) - ok_count

    socket =
      socket
      |> assign(:selection_mode, false)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:confirm_delete, false)
      |> stream(:organizations, Organizations.list_organizations(), reset: true)
      |> put_flash_for_results(ok_count, error_count)

    {:noreply, socket}
  end

  defp put_flash_for_results(socket, ok_count, 0) do
    put_flash(socket, :info, "Deleted #{pluralize(ok_count, "organization", "organizations")}.")
  end

  defp put_flash_for_results(socket, _ok_count, error_count) do
    put_flash(
      socket,
      :error,
      "Could not delete #{pluralize(error_count, "organization", "organizations")}. Try again."
    )
  end

  defp pluralize(1, singular, _plural), do: "1 #{singular}"
  defp pluralize(n, _singular, plural), do: "#{n} #{plural}"
end
