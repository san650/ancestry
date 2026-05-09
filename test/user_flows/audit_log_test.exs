defmodule Web.UserFlows.AuditLogTest do
  use Web.E2ECase

  # Given audit-log rows exist for two organizations
  # When a super-admin visits /admin/audit-log
  # Then they see all rows newest first
  #
  # When an editor visits /admin/audit-log
  # Then they are redirected with a permission error

  setup do
    org_a = insert(:organization, name: "Alpha")
    org_b = insert(:organization, name: "Beta")

    row_a =
      insert(:audit_log,
        organization_id: org_a.id,
        organization_name: org_a.name,
        account_email: "ana@example.com",
        command_module: "Ancestry.Commands.AddCommentToPhoto",
        inserted_at: ~N[2026-05-09 10:00:00]
      )

    row_b =
      insert(:audit_log,
        organization_id: org_b.id,
        organization_name: org_b.name,
        account_email: "bob@example.com",
        command_module: "Ancestry.Commands.AddPhotoToGallery",
        inserted_at: ~N[2026-05-08 10:00:00]
      )

    %{org_a: org_a, org_b: org_b, row_a: row_a, row_b: row_b}
  end

  test "admin sees all audit rows", %{conn: conn, row_a: a, row_b: b} do
    conn
    |> log_in_e2e(role: :admin)
    |> visit(~p"/admin/audit-log")
    |> wait_liveview()
    |> assert_has(test_id("audit-row-#{a.id}"))
    |> assert_has(test_id("audit-row-#{b.id}"))
    |> assert_has(test_id("audit-row-#{a.id}"), text: "AddCommentToPhoto")
    |> assert_has(test_id("audit-row-#{a.id}"), text: "ana@example.com")
    |> assert_has(test_id("audit-row-#{a.id}"), text: "Alpha")
  end

  test "editor cannot access /admin/audit-log", %{conn: conn} do
    conn
    |> log_in_e2e(role: :editor)
    |> visit(~p"/admin/audit-log")
    |> wait_liveview()
    |> assert_has("[role='alert']", text: "permission")
  end
end
