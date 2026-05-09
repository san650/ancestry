defmodule Web.BusUITest do
  use Web.ConnCase, async: true

  alias Phoenix.LiveView.Socket
  import Web.BusUI

  test "{:ok, _} returns {:noreply, socket} unchanged" do
    socket = %Socket{}
    assert {:noreply, ^socket} = handle_dispatch_result({:ok, :anything}, socket)
  end

  test "{:error, :validation, changeset} assigns the form" do
    socket = %Socket{assigns: %{__changed__: %{}}}
    cs = Ecto.Changeset.change(%Ancestry.Comments.PhotoComment{})

    assert {:noreply, %Socket{assigns: %{form: %Phoenix.HTML.Form{}}}} =
             handle_dispatch_result({:error, :validation, cs}, socket)
  end

  test "{:error, :unauthorized} sets a flash" do
    socket = %Socket{assigns: %{flash: %{}, __changed__: %{}}}

    assert {:noreply, %Socket{assigns: %{flash: %{"error" => msg}}}} =
             handle_dispatch_result({:error, :unauthorized}, socket)

    assert msg =~ "permission"
  end

  test "{:error, :not_found} sets a flash" do
    socket = %Socket{assigns: %{flash: %{}, __changed__: %{}}}

    assert {:noreply, %Socket{assigns: %{flash: %{"error" => _}}}} =
             handle_dispatch_result({:error, :not_found}, socket)
  end

  test "{:error, :conflict, _} sets a flash" do
    socket = %Socket{assigns: %{flash: %{}, __changed__: %{}}}

    assert {:noreply, %Socket{}} =
             handle_dispatch_result({:error, :conflict, :stale}, socket)
  end

  test "{:error, :handler, _} sets a flash and logs" do
    socket = %Socket{assigns: %{flash: %{}, __changed__: %{}}}

    assert {:noreply, %Socket{}} =
             handle_dispatch_result({:error, :handler, :boom}, socket)
  end
end
