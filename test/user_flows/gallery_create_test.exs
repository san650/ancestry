defmodule Web.UserFlows.GalleryCreateTest do
  @moduledoc """
  Verifies that creating a gallery via the family-show LiveView dispatches
  `AddGalleryToFamily` through the Bus and writes an audit row.

  ## Scenario

  ### Bus-driven gallery creation

  Given a logged-in admin viewing the family show page
  When the user opens the new-gallery modal
  And submits the form with a valid name
  Then a gallery is created
  And the modal closes and the gallery appears in the side panel
  And an audit_log row is written for `Ancestry.Commands.AddGalleryToFamily`

  ### Validation error path

  Given the same setup
  When the user submits the form with an empty name
  Then no gallery is created
  And no audit_log row is written
  """

  use Web.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ancestry.Audit.Log
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Repo

  setup :register_and_log_in_account

  setup %{account: account} do
    org = insert(:organization)
    family = insert(:family, organization: org)

    Repo.insert!(%Ancestry.Organizations.AccountOrganization{
      account_id: account.id,
      organization_id: org.id
    })

    %{org: org, family: family}
  end

  test "creates a gallery via the bus and writes an audit row",
       %{conn: conn, org: org, family: family} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")

    view |> element("#side-panel-gallery-list-new-btn") |> render_click()
    assert has_element?(view, "#new-gallery-modal")

    view
    |> form("#new-gallery-form", gallery: %{name: "Summer Trip"})
    |> render_submit()

    refute has_element?(view, "#new-gallery-modal")

    assert [gallery] = Repo.all(Gallery)
    assert gallery.name == "Summer Trip"
    assert gallery.family_id == family.id

    assert has_element?(view, "#side-panel-gallery-list-#{gallery.id}", "Summer Trip")

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.AddGalleryToFamily"
    assert row.payload["arguments"]["name"] == "Summer Trip"
    assert row.payload["arguments"]["family_id"] == family.id
  end

  test "shows validation error on empty name and writes no audit row",
       %{conn: conn, org: org, family: family} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}")

    view |> element("#side-panel-gallery-list-new-btn") |> render_click()

    view
    |> form("#new-gallery-form", gallery: %{name: ""})
    |> render_submit()

    assert has_element?(view, "#new-gallery-modal")
    assert Repo.all(Gallery) == []
    assert Repo.all(Log) == []
  end
end
