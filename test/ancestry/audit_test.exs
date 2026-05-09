defmodule Ancestry.AuditTest do
  use Ancestry.DataCase, async: true
  alias Ancestry.Audit

  describe "list_entries/2" do
    test "returns rows newest first" do
      old = insert(:audit_log, inserted_at: ~N[2026-05-01 10:00:00])
      new = insert(:audit_log, inserted_at: ~N[2026-05-09 10:00:00])

      assert [r1, r2] = Audit.list_entries(%{}, 50)
      assert r1.id == new.id
      assert r2.id == old.id
    end

    test "filters by organization_id" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      a = insert(:audit_log, organization_id: org_a.id)
      _b = insert(:audit_log, organization_id: org_b.id)

      assert [row] = Audit.list_entries(%{organization_id: org_a.id}, 50)
      assert row.id == a.id
    end

    test "filters by account_id" do
      acc = insert(:account)
      mine = insert(:audit_log, account_id: acc.id)
      _other = insert(:audit_log, account_id: acc.id + 9999)

      assert [row] = Audit.list_entries(%{account_id: acc.id}, 50)
      assert row.id == mine.id
    end

    test "respects limit" do
      Enum.each(1..5, fn _ -> insert(:audit_log) end)
      assert length(Audit.list_entries(%{}, 3)) == 3
    end

    test "cursor returns strictly older rows" do
      r1 = insert(:audit_log, inserted_at: ~N[2026-05-09 10:00:00])
      r2 = insert(:audit_log, inserted_at: ~N[2026-05-08 10:00:00])
      r3 = insert(:audit_log, inserted_at: ~N[2026-05-07 10:00:00])

      cursor = {r1.inserted_at, r1.id}

      ids = Audit.list_entries(%{before: cursor}, 50) |> Enum.map(& &1.id)
      assert ids == [r2.id, r3.id]
    end

    test "cursor with same-timestamp rows uses id as tiebreaker" do
      ts = ~N[2026-05-09 10:00:00]
      a = insert(:audit_log, inserted_at: ts)
      b = insert(:audit_log, inserted_at: ts)
      [first, second] = if a.id < b.id, do: [b, a], else: [a, b]

      cursor = {first.inserted_at, first.id}
      assert [row] = Audit.list_entries(%{before: cursor}, 50)
      assert row.id == second.id
    end
  end

  describe "get_entry!/1" do
    test "returns the row" do
      row = insert(:audit_log)
      assert %Ancestry.Audit.Log{} = found = Audit.get_entry!(row.id)
      assert found.id == row.id
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn -> Audit.get_entry!(-1) end
    end
  end

  describe "list_correlated_entries/1" do
    test "returns sibling rows in chronological order, including the focal row" do
      cid = "req-#{Ecto.UUID.generate()}"
      a = insert(:audit_log, correlation_id: cid, inserted_at: ~N[2026-05-09 10:00:00])
      b = insert(:audit_log, correlation_id: cid, inserted_at: ~N[2026-05-09 10:00:01])
      _other = insert(:audit_log, correlation_id: "req-other-#{Ecto.UUID.generate()}")

      ids = Audit.list_correlated_entries(cid) |> Enum.map(& &1.id)
      assert ids == [a.id, b.id]
    end

    test "returns single row when no siblings" do
      cid = "req-solo-#{Ecto.UUID.generate()}"
      only = insert(:audit_log, correlation_id: cid)

      assert [row] = Audit.list_correlated_entries(cid)
      assert row.id == only.id
    end
  end

  describe "list_audit_accounts/1" do
    test "returns DISTINCT %{id, email} tuples" do
      acc = insert(:account, email: "a@example.com")
      insert(:audit_log, account_id: acc.id, account_email: acc.email)
      insert(:audit_log, account_id: acc.id, account_email: acc.email)

      assert [%{id: id, email: "a@example.com"}] = Audit.list_audit_accounts(%{})
      assert id == acc.id
    end

    test "scopes to organization_id when provided" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      acc_a = insert(:account, email: "a@x.com")
      acc_b = insert(:account, email: "b@x.com")

      insert(:audit_log,
        account_id: acc_a.id,
        account_email: acc_a.email,
        organization_id: org_a.id
      )

      insert(:audit_log,
        account_id: acc_b.id,
        account_email: acc_b.email,
        organization_id: org_b.id
      )

      assert [%{id: id}] = Audit.list_audit_accounts(%{organization_id: org_a.id})
      assert id == acc_a.id
    end

    test "returns [] when no rows" do
      assert [] = Audit.list_audit_accounts(%{})
    end
  end
end
