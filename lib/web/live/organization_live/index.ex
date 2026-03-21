defmodule Web.OrganizationLive.Index do
  use Web, :live_view

  alias Ancestry.Organizations
  alias Ancestry.Organizations.Organization

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
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
end
