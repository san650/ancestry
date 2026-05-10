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

  test "filter by organization narrows results", %{conn: conn, row_a: a, row_b: b} do
    insert(:account, email: "ana@example.com")

    conn
    |> log_in_e2e(role: :admin)
    |> visit(~p"/admin/audit-log")
    |> wait_liveview()
    |> select("Organization", exact: false, option: "Alpha")
    |> wait_liveview()
    |> assert_has(test_id("audit-row-#{a.id}"))
    |> refute_has(test_id("audit-row-#{b.id}"))
  end

  test "filter by account narrows results", %{conn: conn, row_a: a, row_b: b} do
    conn
    |> log_in_e2e(role: :admin)
    |> visit(~p"/admin/audit-log")
    |> wait_liveview()
    |> select("Account", exact: false, option: "ana@example.com")
    |> wait_liveview()
    |> assert_has(test_id("audit-row-#{a.id}"))
    |> refute_has(test_id("audit-row-#{b.id}"))
  end

  test "combined filters compose", %{conn: conn, row_a: a, row_b: b} do
    conn
    |> log_in_e2e(role: :admin)
    |> visit(~p"/admin/audit-log")
    |> wait_liveview()
    |> select("Organization", exact: false, option: "Alpha")
    |> wait_liveview()
    |> select("Account", exact: false, option: "ana@example.com")
    |> wait_liveview()
    |> assert_has(test_id("audit-row-#{a.id}"))
    |> refute_has(test_id("audit-row-#{b.id}"))
  end

  test "infinite scroll loads older rows", %{conn: conn} do
    Enum.each(1..60, fn i ->
      insert(:audit_log,
        account_email: "user#{i}@example.com",
        inserted_at: NaiveDateTime.add(~N[2026-05-01 10:00:00], -i, :second)
      )
    end)

    last_row =
      Ancestry.Audit.list_entries(%{}, 100)
      |> Enum.find(fn r -> r.account_email == "user60@example.com" end)

    conn
    |> log_in_e2e(role: :admin)
    |> visit(~p"/admin/audit-log")
    |> wait_liveview()
    |> assert_has(test_id("audit-load-more"))
    |> click(test_id("audit-load-more"))
    |> wait_liveview()
    |> assert_has(test_id("audit-row-#{last_row.id}"))
    |> refute_has(test_id("audit-load-more"))
  end

  test "clicking a row expands its full payload", %{conn: conn, row_a: a} do
    conn
    |> log_in_e2e(role: :admin)
    |> visit(~p"/admin/audit-log")
    |> wait_liveview()
    |> click(test_id("audit-row-#{a.id}"))
    |> wait_liveview()
    |> assert_has(test_id("audit-row-expanded-#{a.id}"))
    |> assert_has(test_id("audit-row-expanded-#{a.id}"), text: a.command_id)
    |> assert_has(test_id("audit-row-expanded-#{a.id}"), text: hd(a.correlation_ids))
  end

  test "org-scoped page only shows that org's rows", %{
    conn: conn,
    org_a: org_a,
    row_a: a,
    row_b: b
  } do
    conn
    |> log_in_e2e(role: :admin, organization_ids: [org_a.id])
    |> visit(~p"/org/#{org_a.id}/audit-log")
    |> wait_liveview()
    |> assert_has(test_id("audit-row-#{a.id}"))
    |> refute_has(test_id("audit-row-#{b.id}"))
  end

  test "org-scoped page hides the organization filter", %{conn: conn, org_a: org_a} do
    conn
    |> log_in_e2e(role: :admin, organization_ids: [org_a.id])
    |> visit(~p"/org/#{org_a.id}/audit-log")
    |> wait_liveview()
    |> refute_has(test_id("audit-filter-org"))
    |> assert_has(test_id("audit-filter-account"))
  end

  test "editor cannot access org-scoped audit log", %{conn: conn, org_a: org_a} do
    conn
    |> log_in_e2e(role: :editor, organization_ids: [org_a.id])
    |> visit(~p"/org/#{org_a.id}/audit-log")
    |> wait_liveview()
    |> assert_has("[role='alert']", text: "permission")
  end

  test "detail page shows full record and correlated rows", %{conn: conn} do
    cid = "req-#{Ecto.UUID.generate()}"
    a = insert(:audit_log, correlation_ids: [cid], inserted_at: ~N[2026-05-09 10:00:00])
    b = insert(:audit_log, correlation_ids: [cid], inserted_at: ~N[2026-05-09 10:00:01])

    conn
    |> log_in_e2e(role: :admin)
    |> visit(~p"/admin/audit-log/#{a.id}")
    |> wait_liveview()
    |> assert_has(test_id("audit-detail"), text: a.command_id)
    |> assert_has(test_id("audit-detail"), text: cid)
    |> assert_has(test_id("related-event-#{b.id}"))
  end

  test "detail page shows 'No related events' when alone", %{conn: conn} do
    cid = "req-solo-#{Ecto.UUID.generate()}"
    row = insert(:audit_log, correlation_ids: [cid])

    conn
    |> log_in_e2e(role: :admin)
    |> visit(~p"/admin/audit-log/#{row.id}")
    |> wait_liveview()
    |> assert_has(test_id("audit-detail"), text: "No related events")
  end

  test "nav shows admin audit-log link to admin", %{conn: conn} do
    conn
    |> log_in_e2e(role: :admin)
    |> visit(~p"/admin/accounts")
    |> wait_liveview()
    |> assert_has(test_id("nav-audit-log-admin"))
  end

  test "nav shows org audit-log link inside org context", %{conn: conn, org_a: org_a} do
    conn
    |> log_in_e2e(role: :admin, organization_ids: [org_a.id])
    |> visit(~p"/org/#{org_a.id}")
    |> wait_liveview()
    |> assert_has(test_id("nav-audit-log-org"))
  end

  test "nav hides audit-log links from editor", %{conn: conn, org_a: org_a} do
    conn
    |> log_in_e2e(role: :editor, organization_ids: [org_a.id])
    |> visit(~p"/org/#{org_a.id}")
    |> wait_liveview()
    |> refute_has(test_id("nav-audit-log-admin"))
    |> refute_has(test_id("nav-audit-log-org"))
  end
end
