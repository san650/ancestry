defmodule Web.FamilyLive.Index do
  use Web, :live_view

  alias Ancestry.Families

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:confirm_delete_family, nil)
     |> stream(:families, Families.list_families(socket.assigns.organization.id))}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("request_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_family, Families.get_family!(id))}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete_family, nil)}
  end

  def handle_event("confirm_delete", _, socket) do
    family = socket.assigns.confirm_delete_family
    {:ok, _} = Families.delete_family(family)

    {:noreply,
     socket
     |> assign(:confirm_delete_family, nil)
     |> stream_delete(:families, family)}
  end
end
