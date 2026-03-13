defmodule Web.FamilyLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "family:#{family_id}")
    end

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:editing, false)
     |> assign(:confirm_delete, false)
     |> assign(:form, to_form(Families.change_family(family)))}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("edit", _, socket) do
    form = to_form(Families.change_family(socket.assigns.family))
    {:noreply, socket |> assign(:editing, true) |> assign(:form, form)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("validate", %{"family" => params}, socket) do
    changeset =
      socket.assigns.family
      |> Families.change_family(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"family" => params}, socket) do
    case Families.update_family(socket.assigns.family, params) do
      {:ok, family} ->
        {:noreply,
         socket
         |> assign(:family, family)
         |> assign(:editing, false)
         |> assign(:form, to_form(Families.change_family(family)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    {:ok, _} = Families.delete_family(socket.assigns.family)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:cover_processed, family}, socket) do
    {:noreply, assign(socket, :family, family)}
  end

  def handle_info({:cover_failed, family}, socket) do
    {:noreply, assign(socket, :family, family)}
  end
end
