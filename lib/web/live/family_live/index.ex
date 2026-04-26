defmodule Web.FamilyLive.Index do
  use Web, :live_view

  alias Ancestry.Families

  @impl true
  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_scope.organization.id

    {:ok,
     socket
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete, false)
     |> assign(:show_menu, false)
     |> stream(:families, Families.list_families(org_id))}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_select_mode", _, socket) do
    org_id = socket.assigns.current_scope.organization.id

    {:noreply,
     socket
     |> assign(:selection_mode, !socket.assigns.selection_mode)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete, false)
     |> stream(:families, Families.list_families(org_id), reset: true)}
  end

  def handle_event("toggle_menu", _, socket) do
    {:noreply, assign(socket, :show_menu, !socket.assigns.show_menu)}
  end

  def handle_event("close_menu", _, socket) do
    {:noreply, assign(socket, :show_menu, false)}
  end

  def handle_event("card_clicked", %{"id" => id}, socket) do
    family_id = String.to_integer(id)

    if socket.assigns.selection_mode do
      selected =
        if MapSet.member?(socket.assigns.selected_ids, family_id),
          do: MapSet.delete(socket.assigns.selected_ids, family_id),
          else: MapSet.put(socket.assigns.selected_ids, family_id)

      family = Families.get_family!(family_id)

      {:noreply,
       socket
       |> assign(:selected_ids, selected)
       |> stream_insert(:families, family)}
    else
      {:noreply,
       push_navigate(socket,
         to: ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{family_id}"
       )}
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
    org_id = socket.assigns.current_scope.organization.id

    results =
      Enum.map(selected, fn id ->
        try do
          family = Families.get_family!(id)
          Families.delete_family(family)
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
      |> stream(:families, Families.list_families(org_id), reset: true)
      |> put_flash_for_results(ok_count, error_count)

    {:noreply, socket}
  end

  defp put_flash_for_results(socket, ok_count, 0) do
    put_flash(
      socket,
      :info,
      ngettext("Deleted 1 family.", "Deleted %{count} families.", ok_count)
    )
  end

  defp put_flash_for_results(socket, _ok_count, error_count) do
    put_flash(
      socket,
      :error,
      ngettext(
        "Could not delete 1 family. Try again.",
        "Could not delete %{count} families. Try again.",
        error_count
      )
    )
  end
end
