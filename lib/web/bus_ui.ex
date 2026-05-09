defmodule Web.BusUI do
  @moduledoc """
  Shared LiveView helper for routing `Ancestry.Bus.dispatch/2` results
  through the standard error taxonomy.
  """

  use Gettext, backend: Web.Gettext
  alias Phoenix.Component
  alias Phoenix.LiveView

  def handle_dispatch_result({:ok, _result}, socket), do: {:noreply, socket}

  def handle_dispatch_result({:error, :validation, changeset}, socket),
    do: {:noreply, Component.assign(socket, :form, Component.to_form(changeset))}

  def handle_dispatch_result({:error, :unauthorized}, socket),
    do:
      {:noreply,
       LiveView.put_flash(socket, :error, gettext("You don't have permission to do that."))}

  def handle_dispatch_result({:error, :not_found}, socket),
    do: {:noreply, LiveView.put_flash(socket, :error, gettext("That item no longer exists."))}

  def handle_dispatch_result({:error, :conflict, _term}, socket),
    do:
      {:noreply,
       LiveView.put_flash(
         socket,
         :error,
         gettext("That action conflicted with another change. Please retry.")
       )}

  def handle_dispatch_result({:error, :handler, term}, socket) do
    require Logger
    Logger.error("command failed", error: inspect(term))
    {:noreply, LiveView.put_flash(socket, :error, gettext("Something went wrong."))}
  end
end
