defmodule Web.GalleryLive.IndexTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families
  alias Ancestry.Galleries

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    {:ok, gallery} = Galleries.create_gallery(%{name: "Summer 2025", family_id: family.id})
    %{gallery: gallery, family: family}
  end

  test "lists all galleries", %{conn: conn, gallery: gallery, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/galleries")
    assert html =~ gallery.name
  end

  test "opens new gallery modal", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries")
    refute has_element?(view, "#new-gallery-modal")
    view |> element("#open-new-gallery-btn") |> render_click()
    assert has_element?(view, "#new-gallery-modal")
  end

  test "creates a gallery via the new gallery modal", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries")
    view |> element("#open-new-gallery-btn") |> render_click()

    view
    |> form("#new-gallery-form", gallery: %{name: "Winter 2025"})
    |> render_submit()

    assert has_element?(view, "[data-gallery-name]", "Winter 2025")
  end

  test "shows validation error for blank gallery name", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries")
    view |> element("#open-new-gallery-btn") |> render_click()

    view
    |> form("#new-gallery-form", gallery: %{name: ""})
    |> render_submit()

    assert has_element?(view, "#new-gallery-form .text-error")
  end

  test "deletes a gallery after confirmation", %{conn: conn, gallery: gallery, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries")

    view |> element("#delete-gallery-#{gallery.id}") |> render_click()
    assert has_element?(view, "#confirm-delete-modal")

    view |> element("#confirm-delete-modal [phx-click='confirm_delete']") |> render_click()
    refute has_element?(view, "#gallery-#{gallery.id}")
  end
end
