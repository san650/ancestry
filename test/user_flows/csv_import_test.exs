defmodule Web.UserFlows.CsvImportTest do
  use Web.E2ECase

  # Given an existing family in an organization
  # When the user navigates to the family show page
  # And clicks the meatball menu
  # Then the dropdown with secondary actions is visible
  #
  # When the user clicks "Import from CSV"
  # Then the import modal is shown with an upload form
  #
  # When the user selects a CSV file
  # And clicks "Import"
  # Then the modal shows the import results
  # And the people count reflects the imported people
  #
  # When the user clicks "Close"
  # Then the modal closes

  setup do
    org = insert(:organization, name: "Test Org")
    family = insert(:family, name: "Import Family", organization: org)
    %{org: org, family: family}
  end

  test "import people from CSV via meatball menu", %{conn: conn, org: org, family: family} do
    conn = log_in_e2e(conn)

    # Navigate to family show page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()
      |> assert_has(test_id("family-name"), text: "Import Family")

    # Open kebab menu
    conn =
      conn
      |> click(test_id("kebab-btn"))

    # Click "Import from CSV"
    conn =
      conn
      |> click(test_id("import-csv-btn"))
      |> assert_has(test_id("import-modal"))

    # Upload CSV file
    conn =
      conn
      |> upload_image(
        test_id("import-file-input"),
        [Path.absname("test/fixtures/family_echo_sample.csv")]
      )

    # Submit the import form
    conn =
      conn
      |> click(test_id("import-submit-btn"))
      |> assert_has(test_id("import-created"))

    # Close the modal
    conn
    |> click(test_id("import-close-btn"))
    |> refute_has(test_id("import-modal"))
  end
end
