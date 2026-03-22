# Expand Partner Relationships Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `partner`/`ex_partner` relationship types with four descriptive types (`married`, `relationship`, `divorced`, `separated`), each with custom metadata schemas, and update all UI surfaces accordingly.

**Architecture:** New metadata embedded schemas per type, PolymorphicEmbed keyed by type string, helper functions for grouping active vs former partner types. In-place type updates replace the old delete+recreate conversion. Application-level validation ensures one partner-type relationship per pair.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, PolymorphicEmbed, PostgreSQL (jsonb metadata)

**Spec:** `docs/superpowers/specs/2026-03-21-expand-partner-relationships-design.md`

---

## File Structure

### New Files
- `lib/ancestry/relationships/metadata/married_metadata.ex` — Marriage date + location
- `lib/ancestry/relationships/metadata/relationship_metadata.ex` — Empty schema
- `lib/ancestry/relationships/metadata/divorced_metadata.ex` — Marriage + divorce fields
- `lib/ancestry/relationships/metadata/separated_metadata.ex` — Marriage + separation fields
- `priv/repo/migrations/TIMESTAMP_expand_partner_relationship_types.exs` — Data migration

### Files to Delete
- `lib/ancestry/relationships/metadata/partner_metadata.ex`
- `lib/ancestry/relationships/metadata/ex_partner_metadata.ex`

### Files to Modify
- `lib/ancestry/relationships/relationship.ex` — Types, helpers, polymorphic embed config
- `lib/ancestry/relationships.ex` — Query functions, `update_partner_type/3`, one-per-pair validation
- `lib/ancestry/people/person_tree.ex` — Use new query function names, nil-safe sorting
- `lib/web/live/person_live/show.ex` — Remove convert-to-ex, unified edit, partner titles
- `lib/web/live/person_live/show.html.heex` — Template updates for all partner UI
- `lib/web/live/shared/add_relationship_component.ex` — Type dropdown, save flow
- `lib/ancestry/import/csv/family_echo.ex` — New type atoms
- `lib/ancestry/import/csv/adapter.ex` — Updated docs
- `priv/repo/seeds.exs` — New type strings

### Tests to Modify
- `test/ancestry/relationships_test.exs`
- `test/web/live/person_live/relationships_test.exs`
- `test/web/live/family_live/tree_multiple_partners_test.exs`
- `test/web/live/family_live/tree_add_relationship_test.exs`
- `test/ancestry/import/csv/family_echo_test.exs`
- `test/ancestry/import/csv_test.exs`
- `test/user_flows/manage_people_test.exs`

---

## Task 1: New Metadata Schemas

**Files:**
- Create: `lib/ancestry/relationships/metadata/married_metadata.ex`
- Create: `lib/ancestry/relationships/metadata/relationship_metadata.ex`
- Create: `lib/ancestry/relationships/metadata/divorced_metadata.ex`
- Create: `lib/ancestry/relationships/metadata/separated_metadata.ex`
- Delete: `lib/ancestry/relationships/metadata/partner_metadata.ex`
- Delete: `lib/ancestry/relationships/metadata/ex_partner_metadata.ex`

- [ ] **Step 1: Create `MarriedMetadata`**

Same fields as old `PartnerMetadata`: `marriage_day`, `marriage_month`, `marriage_year`, `marriage_location`.

```elixir
# lib/ancestry/relationships/metadata/married_metadata.ex
defmodule Ancestry.Relationships.Metadata.MarriedMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :marriage_day, :integer
    field :marriage_month, :integer
    field :marriage_year, :integer
    field :marriage_location, :string
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:marriage_day, :marriage_month, :marriage_year, :marriage_location])
    |> validate_number(:marriage_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:marriage_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:marriage_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
  end
end
```

- [ ] **Step 2: Create `RelationshipMetadata`**

Empty embedded schema — no additional fields.

```elixir
# lib/ancestry/relationships/metadata/relationship_metadata.ex
defmodule Ancestry.Relationships.Metadata.RelationshipMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
  end

  def changeset(struct, params) do
    cast(struct, params, [])
  end
end
```

- [ ] **Step 3: Create `DivorcedMetadata`**

Same as old `ExPartnerMetadata`: marriage fields + divorce fields.

```elixir
# lib/ancestry/relationships/metadata/divorced_metadata.ex
defmodule Ancestry.Relationships.Metadata.DivorcedMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :marriage_day, :integer
    field :marriage_month, :integer
    field :marriage_year, :integer
    field :marriage_location, :string
    field :divorce_day, :integer
    field :divorce_month, :integer
    field :divorce_year, :integer
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [
      :marriage_day, :marriage_month, :marriage_year, :marriage_location,
      :divorce_day, :divorce_month, :divorce_year
    ])
    |> validate_number(:marriage_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:marriage_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:marriage_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
    |> validate_number(:divorce_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:divorce_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:divorce_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
  end
end
```

- [ ] **Step 4: Create `SeparatedMetadata`**

Marriage fields + separation date fields.

```elixir
# lib/ancestry/relationships/metadata/separated_metadata.ex
defmodule Ancestry.Relationships.Metadata.SeparatedMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :marriage_day, :integer
    field :marriage_month, :integer
    field :marriage_year, :integer
    field :marriage_location, :string
    field :separated_day, :integer
    field :separated_month, :integer
    field :separated_year, :integer
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [
      :marriage_day, :marriage_month, :marriage_year, :marriage_location,
      :separated_day, :separated_month, :separated_year
    ])
    |> validate_number(:marriage_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:marriage_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:marriage_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
    |> validate_number(:separated_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:separated_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:separated_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
  end
end
```

- [ ] **Step 5: Delete old metadata files**

```bash
rm lib/ancestry/relationships/metadata/partner_metadata.ex
rm lib/ancestry/relationships/metadata/ex_partner_metadata.ex
```

- [ ] **Step 6: Commit**

```bash
git add -A lib/ancestry/relationships/metadata/
git commit -m "Replace partner/ex_partner metadata with four new type schemas"
```

---

## Task 2: Update Relationship Schema

**Files:**
- Modify: `lib/ancestry/relationships/relationship.ex`

- [ ] **Step 1: Update the schema**

Replace the full content of `lib/ancestry/relationships/relationship.ex`:

```elixir
defmodule Ancestry.Relationships.Relationship do
  use Ecto.Schema
  import Ecto.Changeset
  import PolymorphicEmbed

  schema "relationships" do
    field :person_a_id, :integer
    field :person_b_id, :integer
    field :type, :string

    polymorphic_embeds_one(:metadata,
      types: [
        parent: Ancestry.Relationships.Metadata.ParentMetadata,
        married: Ancestry.Relationships.Metadata.MarriedMetadata,
        relationship: Ancestry.Relationships.Metadata.RelationshipMetadata,
        divorced: Ancestry.Relationships.Metadata.DivorcedMetadata,
        separated: Ancestry.Relationships.Metadata.SeparatedMetadata
      ],
      type_field_name: :__type__,
      on_type_not_found: :raise,
      on_replace: :update
    )

    timestamps()
  end

  @valid_types ~w(parent married relationship divorced separated)
  @partner_types ~w(married relationship divorced separated)
  @active_partner_types ~w(married relationship)
  @former_partner_types ~w(divorced separated)

  def partner_type?(type), do: type in @partner_types
  def active_partner_type?(type), do: type in @active_partner_types
  def former_partner_type?(type), do: type in @former_partner_types

  def partner_types, do: @partner_types
  def active_partner_types, do: @active_partner_types
  def former_partner_types, do: @former_partner_types

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:person_a_id, :person_b_id, :type])
    |> validate_required([:person_a_id, :person_b_id, :type])
    |> validate_inclusion(:type, @valid_types)
    |> validate_different_persons()
    |> maybe_order_symmetric_ids()
    |> cast_polymorphic_embed(:metadata, required: false)
    |> unique_constraint([:person_a_id, :person_b_id, :type],
      name: :relationships_person_a_id_person_b_id_type_index,
      message: "relationship already exists"
    )
  end

  defp validate_different_persons(changeset) do
    a = get_field(changeset, :person_a_id)
    b = get_field(changeset, :person_b_id)

    if a && b && a == b do
      add_error(changeset, :person_b_id, "cannot be the same person")
    else
      changeset
    end
  end

  defp maybe_order_symmetric_ids(changeset) do
    type = get_field(changeset, :type)
    a = get_field(changeset, :person_a_id)
    b = get_field(changeset, :person_b_id)

    if partner_type?(type) && a && b && a > b do
      changeset
      |> put_change(:person_a_id, b)
      |> put_change(:person_b_id, a)
    else
      changeset
    end
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles with warnings about unused functions in old callers (relationships.ex, show.ex, etc) — these are expected at this stage and will be fixed in subsequent tasks.

- [ ] **Step 3: Commit**

```bash
git add lib/ancestry/relationships/relationship.ex
git commit -m "Update Relationship schema with new partner types and helper functions"
```

---

## Task 3: Update Relationship Context

**Files:**
- Modify: `lib/ancestry/relationships.ex`
- Test: `test/ancestry/relationships_test.exs`

- [ ] **Step 1: Update tests for new type strings**

In `test/ancestry/relationships_test.exs`, make these changes:

1. In `"valid partner changeset with symmetric ID ordering"` test: change `"partner"` → `"married"` and `__type__: "partner"` → `__type__: "married"` (lines 23-28)
2. In `"rejects same person on both sides"` test: change `"partner"` → `"married"` (line 51)
3. In `"creates a partner relationship with symmetric ordering"` test: change `"partner"` → `"married"` (line 92)
4. In `"get_partners/1"` describe: rename to `"get_active_partners/1"`, change `"partner"` → `"married"` in create calls (lines 273, 295-296), change `get_partners` → `get_active_partners` in assert calls (lines 275, 280, 298, 300)
5. In `"get_ex_partners/1"` describe: rename to `"get_former_partners/1"`, change `"ex_partner"` → `"divorced"` in create calls (lines 314, 335, 341), change `get_ex_partners` → `get_former_partners` in assert calls (lines 319, 346, 348)
6. In `"update_relationship/2"` test: change `"partner"` → `"married"` in create call and metadata `__type__` (lines 148, 152)
7. Rewrite `"convert_to_ex_partner/2"` describe to test `"update_partner_type/3"` instead:

```elixir
describe "update_partner_type/3" do
  test "changes married to divorced carrying marriage metadata" do
    family = family_fixture()
    {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
    {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

    {:ok, rel} =
      Relationships.create_relationship(a, b, "married", %{
        marriage_year: 2020,
        marriage_location: "Paris"
      })

    assert {:ok, updated} =
             Relationships.update_partner_type(rel, "divorced", %{divorce_year: 2023})

    assert updated.type == "divorced"
    assert updated.metadata.marriage_year == 2020
    assert updated.metadata.marriage_location == "Paris"
    assert updated.metadata.divorce_year == 2023
  end

  test "changes relationship to separated" do
    family = family_fixture()
    {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
    {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

    {:ok, rel} = Relationships.create_relationship(a, b, "relationship")

    assert {:ok, updated} =
             Relationships.update_partner_type(rel, "separated", %{separated_year: 2023})

    assert updated.type == "separated"
    assert updated.metadata.separated_year == 2023
  end

  test "changes divorced back to married" do
    family = family_fixture()
    {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
    {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

    {:ok, rel} =
      Relationships.create_relationship(a, b, "divorced", %{
        marriage_year: 2015,
        divorce_year: 2020
      })

    assert {:ok, updated} =
             Relationships.update_partner_type(rel, "married", %{marriage_year: 2022})

    assert updated.type == "married"
    assert updated.metadata.marriage_year == 2022
  end
end
```

8. Add a new test for one-partner-per-pair validation:

```elixir
describe "one partner-type relationship per pair" do
  test "prevents creating a second partner-type relationship" do
    family = family_fixture()
    {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
    {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

    {:ok, _} = Relationships.create_relationship(a, b, "married", %{marriage_year: 2020})
    assert {:error, :partner_relationship_exists} = Relationships.create_relationship(a, b, "divorced")
  end
end
```

9. In `"list_relationships_for_family/1"` describe: change `"partner"` → `"married"` in create calls (lines 575, 587, 598) and update the type assertion (line 603): `assert types == ["married", "parent"]`

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/ancestry/relationships_test.exs`
Expected: FAIL — old function names and types not found yet

- [ ] **Step 3: Update context implementation**

Replace the full content of `lib/ancestry/relationships.ex`. Key changes:

1. Replace `get_partners/2` with `get_active_partners/2`
2. Replace `get_ex_partners/2` with `get_former_partners/2`
3. Update `get_relationship_partners/3` to accept a list of types and use `r.type in ^types`
4. Remove `convert_to_ex_partner/2`, add `update_partner_type/3`
5. Add `validate_unique_partner_pair/3` validation in `create_relationship/4`

```elixir
defmodule Ancestry.Relationships do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.FamilyMember
  alias Ancestry.People.Person
  alias Ancestry.Relationships.Relationship

  def create_relationship(person_a, person_b, type, metadata_attrs \\ %{}) do
    attrs = %{
      person_a_id: person_a.id,
      person_b_id: person_b.id,
      type: type,
      metadata: Map.put(metadata_attrs, :__type__, type)
    }

    with :ok <- validate_parent_limit(person_b.id, type),
         :ok <- validate_unique_partner_pair(person_a.id, person_b.id, type) do
      %Relationship{}
      |> Relationship.changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_relationship(%Relationship{} = rel, attrs) do
    rel
    |> Relationship.changeset(attrs)
    |> Repo.update()
  end

  def delete_relationship(%Relationship{} = rel) do
    Repo.delete(rel)
  end

  @doc """
  Changes a partner-type relationship to a new partner type, carrying over
  overlapping metadata fields and merging new metadata attributes.
  """
  def update_partner_type(%Relationship{} = rel, new_type, new_metadata_attrs \\ %{}) do
    carried = carry_over_metadata(rel.metadata, new_type)
    merged = Map.merge(carried, new_metadata_attrs)

    attrs = %{
      type: new_type,
      metadata: Map.put(merged, :__type__, new_type)
    }

    rel
    |> Relationship.changeset(attrs)
    |> Repo.update()
  end

  defp carry_over_metadata(nil, _new_type), do: %{}

  defp carry_over_metadata(old_metadata, new_type) do
    target_fields = metadata_fields_for_type(new_type)

    old_metadata
    |> Map.from_struct()
    |> Map.take(target_fields)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp metadata_fields_for_type("married"),
    do: [:marriage_day, :marriage_month, :marriage_year, :marriage_location]

  defp metadata_fields_for_type("relationship"), do: []

  defp metadata_fields_for_type("divorced"),
    do: [
      :marriage_day, :marriage_month, :marriage_year, :marriage_location,
      :divorce_day, :divorce_month, :divorce_year
    ]

  defp metadata_fields_for_type("separated"),
    do: [
      :marriage_day, :marriage_month, :marriage_year, :marriage_location,
      :separated_day, :separated_month, :separated_year
    ]

  defp metadata_fields_for_type(_), do: []

  def list_relationships_for_person(person_id) do
    Repo.all(
      from r in Relationship,
        where: r.person_a_id == ^person_id or r.person_b_id == ^person_id
    )
  end

  @doc """
  Returns all relationships where both person_a and person_b are members of the given family.
  """
  def list_relationships_for_family(family_id) do
    from(r in Relationship,
      join: fm_a in FamilyMember,
      on: fm_a.person_id == r.person_a_id and fm_a.family_id == ^family_id,
      join: fm_b in FamilyMember,
      on: fm_b.person_id == r.person_b_id and fm_b.family_id == ^family_id
    )
    |> Repo.all()
  end

  def change_relationship(%Relationship{} = rel, attrs \\ %{}) do
    Relationship.changeset(rel, attrs)
  end

  @doc """
  Returns list of `{person, relationship}` tuples where person is a parent of the given person_id.
  """
  def get_parents(person_id, opts \\ []) do
    query =
      from(r in Relationship,
        join: p in Person,
        on: p.id == r.person_a_id,
        where: r.person_b_id == ^person_id and r.type == "parent",
        select: {p, r}
      )

    query = maybe_filter_by_family(query, opts[:family_id])

    Repo.all(query)
  end

  @doc """
  Returns list of persons who are children of the given person_id.
  """
  def get_children(person_id, opts \\ []) do
    query =
      from(r in Relationship,
        join: p in Person,
        on: p.id == r.person_b_id,
        where: r.person_a_id == ^person_id and r.type == "parent",
        order_by: [asc_nulls_last: p.birth_year, asc: p.id],
        select: p
      )

    query = maybe_filter_by_family(query, opts[:family_id])

    Repo.all(query)
  end

  @doc """
  Returns all children of person_id with their co-parent (if any).
  Returns `[{child, coparent | nil}]`.
  """
  def get_children_with_coparents(person_id) do
    from(child in Person,
      join: r1 in Relationship,
      on: r1.person_b_id == child.id and r1.person_a_id == ^person_id and r1.type == "parent",
      left_join: r2 in Relationship,
      on: r2.person_b_id == child.id and r2.type == "parent" and r2.person_a_id != ^person_id,
      left_join: coparent in Person,
      on: coparent.id == r2.person_a_id,
      select: {child, coparent}
    )
    |> Repo.all()
  end

  @doc """
  Returns list of `{person, relationship}` tuples for active partners (married, relationship).
  """
  def get_active_partners(person_id, opts \\ []) do
    get_relationship_partners(person_id, Relationship.active_partner_types(), opts)
  end

  @doc """
  Returns list of `{person, relationship}` tuples for former partners (divorced, separated).
  """
  def get_former_partners(person_id, opts \\ []) do
    get_relationship_partners(person_id, Relationship.former_partner_types(), opts)
  end

  @doc """
  Returns the partner-type relationship between two people (any partner type), or nil.
  """
  def get_partner_relationship(person_a_id, person_b_id) do
    {a, b} = if person_a_id < person_b_id, do: {person_a_id, person_b_id}, else: {person_b_id, person_a_id}
    types = Relationship.partner_types()

    Repo.one(
      from r in Relationship,
        where: r.person_a_id == ^a and r.person_b_id == ^b and r.type in ^types
    )
  end

  defp get_relationship_partners(person_id, types, opts) do
    family_id = opts[:family_id]

    as_a =
      from(r in Relationship,
        join: p in Person,
        on: p.id == r.person_b_id,
        where: r.person_a_id == ^person_id and r.type in ^types,
        select: {p, r}
      )

    as_b =
      from(r in Relationship,
        join: p in Person,
        on: p.id == r.person_a_id,
        where: r.person_b_id == ^person_id and r.type in ^types,
        select: {p, r}
      )

    as_a = maybe_filter_by_family(as_a, family_id)
    as_b = maybe_filter_by_family(as_b, family_id)

    Repo.all(as_a) ++ Repo.all(as_b)
  end

  @doc """
  Returns list of persons who have BOTH parent_a and parent_b as parents.
  """
  def get_children_of_pair(parent_a_id, parent_b_id, opts \\ []) do
    query =
      from(p in Person,
        join: r1 in Relationship,
        on: r1.person_b_id == p.id and r1.person_a_id == ^parent_a_id and r1.type == "parent",
        join: r2 in Relationship,
        on: r2.person_b_id == p.id and r2.person_a_id == ^parent_b_id and r2.type == "parent",
        order_by: [asc_nulls_last: p.birth_year, asc: p.id],
        select: p
      )

    query = maybe_filter_person_by_family(query, opts[:family_id])

    Repo.all(query)
  end

  @doc """
  Returns list of persons who are children of person_id but do NOT have a second parent.
  """
  def get_solo_children(person_id, opts \\ []) do
    query =
      from(p in Person,
        join: r in Relationship,
        on: r.person_b_id == p.id and r.person_a_id == ^person_id and r.type == "parent",
        left_join: r2 in Relationship,
        on: r2.person_b_id == p.id and r2.type == "parent" and r2.person_a_id != ^person_id,
        where: is_nil(r2.id),
        order_by: [asc_nulls_last: p.birth_year, asc: p.id],
        select: p
      )

    query = maybe_filter_person_by_family(query, opts[:family_id])

    Repo.all(query)
  end

  @doc """
  Returns siblings inferred from shared parents. Returns a mixed list:
  - `{person, parent_a_id, parent_b_id}` for full siblings (share both parents)
  - `{person, shared_parent_id}` for half-siblings (share one parent)
  """
  def get_siblings(person_id) do
    parent_ids =
      from(r in Relationship,
        where: r.person_b_id == ^person_id and r.type == "parent",
        select: r.person_a_id
      )
      |> Repo.all()

    case parent_ids do
      [] ->
        []

      [single_parent_id] ->
        from(p in Person,
          join: r in Relationship,
          on: r.person_b_id == p.id and r.person_a_id == ^single_parent_id and r.type == "parent",
          where: p.id != ^person_id,
          select: p
        )
        |> Repo.all()
        |> Enum.map(fn person -> {person, single_parent_id} end)

      [parent1_id, parent2_id] ->
        sibling_candidates =
          from(p in Person,
            join: r in Relationship,
            on: r.person_b_id == p.id and r.type == "parent",
            where: r.person_a_id in ^parent_ids and p.id != ^person_id,
            group_by: p.id,
            select: {p, fragment("array_agg(?)", r.person_a_id)}
          )
          |> Repo.all()

        both_parents = MapSet.new([parent1_id, parent2_id])

        Enum.map(sibling_candidates, fn {person, shared_ids} ->
          shared_set = MapSet.new(shared_ids)

          if MapSet.equal?(shared_set, both_parents) do
            [pa, pb] = Enum.sort([parent1_id, parent2_id])
            {person, pa, pb}
          else
            shared_parent_id = shared_ids |> Enum.find(&(&1 in parent_ids))
            {person, shared_parent_id}
          end
        end)
    end
  end

  defp maybe_filter_by_family(query, nil), do: query

  defp maybe_filter_by_family(query, family_id) do
    from [_r, p] in query,
      join: fm in FamilyMember,
      on: fm.person_id == p.id and fm.family_id == ^family_id
  end

  defp maybe_filter_person_by_family(query, nil), do: query

  defp maybe_filter_person_by_family(query, family_id) do
    from [p, ...] in query,
      join: fm in FamilyMember,
      on: fm.person_id == p.id and fm.family_id == ^family_id
  end

  defp validate_parent_limit(child_id, "parent") do
    count =
      Repo.aggregate(
        from(r in Relationship, where: r.person_b_id == ^child_id and r.type == "parent"),
        :count
      )

    if count >= 2, do: {:error, :max_parents_reached}, else: :ok
  end

  defp validate_parent_limit(_child_id, _type), do: :ok

  defp validate_unique_partner_pair(person_a_id, person_b_id, type) do
    if Relationship.partner_type?(type) do
      {a, b} = if person_a_id < person_b_id, do: {person_a_id, person_b_id}, else: {person_b_id, person_a_id}
      partner_types = Relationship.partner_types()

      exists? =
        Repo.exists?(
          from r in Relationship,
            where: r.person_a_id == ^a and r.person_b_id == ^b and r.type in ^partner_types
        )

      if exists?, do: {:error, :partner_relationship_exists}, else: :ok
    else
      :ok
    end
  end
end
```

- [ ] **Step 4: Run the tests**

Run: `mix test test/ancestry/relationships_test.exs`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/relationships.ex test/ancestry/relationships_test.exs
git commit -m "Update Relationships context with new partner types and query functions"
```

---

## Task 4: Update PersonTree

**Files:**
- Modify: `lib/ancestry/people/person_tree.ex`
- Test: `test/web/live/family_live/tree_multiple_partners_test.exs`

- [ ] **Step 1: Update tree test types**

In `test/web/live/family_live/tree_multiple_partners_test.exs`:
- Change all `"partner"` → `"married"` in `Relationships.create_relationship` calls (lines 28, 32)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/web/live/family_live/tree_multiple_partners_test.exs`
Expected: FAIL — `get_partners` no longer exists

- [ ] **Step 3: Update PersonTree**

In `lib/ancestry/people/person_tree.ex`:

1. Line 43: `Relationships.get_partners(person.id, opts)` → `Relationships.get_active_partners(person.id, opts)`
2. Line 44: `Relationships.get_ex_partners(person.id, opts)` → `Relationships.get_former_partners(person.id, opts)`
3. Line 51: Make sorting nil-safe for `RelationshipMetadata` (which has no `marriage_year`):
   ```elixir
   year = if rel.metadata, do: Map.get(rel.metadata, :marriage_year), else: nil
   ```
4. Line 117: `Relationships.get_partners(child.id, opts)` → `Relationships.get_active_partners(child.id, opts)`

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/web/live/family_live/tree_multiple_partners_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_tree.ex test/web/live/family_live/tree_multiple_partners_test.exs
git commit -m "Update PersonTree to use new active/former partner query functions"
```

---

## Task 5: Update Person Show Page (LiveView)

**Files:**
- Modify: `lib/web/live/person_live/show.ex`

- [ ] **Step 1: Update `load_relationships/2`**

In `lib/web/live/person_live/show.ex`:

1. Line 397: `Relationships.get_partners(person.id)` → `Relationships.get_active_partners(person.id)`
2. Line 398: `Relationships.get_ex_partners(person.id)` → `Relationships.get_former_partners(person.id)`
3. Lines 437-449: Update `parents_marriage` lookup to check all partner types:
   ```elixir
   parents_marriage =
     case parents do
       [{p1, _}, {p2, _}] ->
         Relationships.get_partner_relationship(p1.id, p2.id)
       _ ->
         nil
     end
   ```
4. Remove assigns `:converting_to_ex` and `:ex_form` from `load_relationships/2` (lines 461-462)

- [ ] **Step 2: Remove convert-to-ex event handlers**

Remove `handle_event("convert_to_ex", ...)` (lines 179-186), `handle_event("cancel_convert_to_ex", ...)` (lines 188-193), `handle_event("save_convert_to_ex", ...)` (lines 195-214).

- [ ] **Step 3: Update `handle_event("edit_relationship", ...)`**

Replace lines 216-250 with a unified handler that works for all partner types:

```elixir
def handle_event("edit_relationship", %{"id" => rel_id}, socket) do
  rel = Ancestry.Repo.get!(Ancestry.Relationships.Relationship, rel_id)

  form_data =
    case rel.type do
      "parent" ->
        %{"role" => rel.metadata && rel.metadata.role}

      type when type in ~w(married relationship divorced separated) ->
        base = %{"partner_subtype" => rel.type}

        metadata_fields =
          if rel.metadata do
            rel.metadata
            |> Map.from_struct()
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
            |> Map.new()
          else
            %{}
          end

        Map.merge(base, metadata_fields)

      _ ->
        %{}
    end

  {:noreply,
   socket
   |> assign(:editing_relationship, rel)
   |> assign(:edit_relationship_form, to_form(form_data, as: :metadata))}
end
```

- [ ] **Step 4: Update `handle_event("save_edit_relationship", ...)`**

Replace lines 259-278:

```elixir
def handle_event("save_edit_relationship", %{"metadata" => metadata_params}, socket) do
  rel = socket.assigns.editing_relationship

  result =
    if Ancestry.Relationships.Relationship.partner_type?(rel.type) do
      new_type = Map.get(metadata_params, "partner_subtype", rel.type)
      metadata = metadata_params |> Map.delete("partner_subtype") |> atomize_metadata()

      if new_type != rel.type do
        Relationships.update_partner_type(rel, new_type, metadata)
      else
        attrs = %{metadata: Map.put(metadata, :__type__, rel.type)}
        Relationships.update_relationship(rel, attrs)
      end
    else
      attrs = %{metadata: Map.put(atomize_metadata(metadata_params), :__type__, rel.type)}
      Relationships.update_relationship(rel, attrs)
    end

  case result do
    {:ok, _} ->
      {:noreply,
       socket
       |> load_relationships(socket.assigns.person)
       |> assign(:editing_relationship, nil)
       |> assign(:edit_relationship_form, nil)
       |> put_flash(:info, "Relationship updated")}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to update relationship")}
  end
end
```

- [ ] **Step 5: Update `atomize_metadata/1`**

Add `:separated_day`, `:separated_month`, `:separated_year` to the integer parsing whitelist (line 487-493). Also filter out `:partner_subtype`:

```elixir
defp atomize_metadata(params) do
  params
  |> Map.delete("partner_subtype")
  |> Map.new(fn {k, v} ->
    key =
      if is_binary(k) do
        String.to_existing_atom(k)
      else
        k
      end

    val =
      if is_binary(v) and v != "" and
           key in [
             :marriage_day, :marriage_month, :marriage_year,
             :divorce_day, :divorce_month, :divorce_year,
             :separated_day, :separated_month, :separated_year
           ] do
        case Integer.parse(v) do
          {int, ""} -> int
          _ -> v
        end
      else
        v
      end

    {key, val}
  end)
end
```

- [ ] **Step 6: Update `format_marriage_info/1`**

Make it nil-safe using `Map.get/3`:

```elixir
defp format_marriage_info(%Ancestry.Relationships.Metadata.RelationshipMetadata{}), do: nil

defp format_marriage_info(metadata) do
  date =
    format_partial_date(
      Map.get(metadata, :marriage_day),
      Map.get(metadata, :marriage_month),
      Map.get(metadata, :marriage_year)
    )

  location = Map.get(metadata, :marriage_location)

  parts =
    [date, location]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))

  if parts == [], do: nil, else: Enum.join(parts, " - ")
end
```

- [ ] **Step 7: Add partner section title helper**

```elixir
defp partner_section_title(rel, partner) do
  cond do
    Ancestry.Relationships.Relationship.former_partner_type?(rel.type) -> "Ex-partner"
    partner.deceased -> "Late partner"
    true -> "Partner"
  end
end
```

- [ ] **Step 8: Add `validate_edit_relationship` event handler**

This handles `phx-change` on the edit relationship modal so the type dropdown dynamically shows/hides metadata fields:

```elixir
def handle_event("validate_edit_relationship", %{"metadata" => metadata_params}, socket) do
  {:noreply, assign(socket, :edit_relationship_form, to_form(metadata_params, as: :metadata))}
end
```

- [ ] **Step 9: Compile check**

Run: `mix compile --warnings-as-errors`
Expected: Compiles (template warnings may appear until template is updated)

- [ ] **Step 10: Commit**

```bash
git add lib/web/live/person_live/show.ex
git commit -m "Update person show LiveView for new partner types and unified edit flow"
```

---

## Task 6: Update Person Show Template

**Files:**
- Modify: `lib/web/live/person_live/show.html.heex`
- Test: `test/web/live/person_live/relationships_test.exs`

- [ ] **Step 1: Update partner tests**

In `test/web/live/person_live/relationships_test.exs`, change `"partner"` → `"married"` in create calls (line 30). Change `"ex_partner"` to `"divorced"` where applicable. Add assertions for partner section titles if tests check for that content.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/web/live/person_live/relationships_test.exs`
Expected: FAIL

- [ ] **Step 3: Update template — partner group section titles**

In `show.html.heex`, inside the partner groups loop (around line 197), add a section title above each partner group:

```heex
<%= for {partner, rel, children} <- @partner_children do %>
  <div
    id={"partner-group-#{partner.id}"}
    class="rounded-xl border border-base-300 p-4 space-y-3"
  >
    <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wide">
      {partner_section_title(rel, partner)}
    </p>
```

- [ ] **Step 4: Update template — replace "Mark as ex-partner" button**

Replace the convert-to-ex button block (lines 265-274) with an edit button:

```heex
<%!-- Edit partnership button for all partner types --%>
<button
  id={"edit-partnership-#{rel.id}"}
  phx-click="edit_relationship"
  phx-value-id={rel.id}
  class="text-xs text-base-content/40 hover:text-primary px-2 py-1 rounded transition-colors"
>
  Edit partnership
</button>
```

- [ ] **Step 5: Update template — metadata display for new types**

Replace the marriage/divorce info block (lines 237-262) to handle all types:

```heex
<%= if rel.metadata do %>
  <% marriage_info = format_marriage_info(rel.metadata) %>
  <%= if marriage_info do %>
    <p class="text-xs text-base-content/40 px-2 flex items-center gap-1">
      <.icon name="hero-heart" class="w-3 h-3" />
      <%= cond do %>
        <% rel.type in ~w(divorced separated) -> %>
          Married: {marriage_info}
        <% true -> %>
          {marriage_info}
      <% end %>
    </p>
  <% end %>
  <%= if rel.type == "divorced" do %>
    <% divorce_info =
      format_partial_date(
        Map.get(rel.metadata, :divorce_day),
        Map.get(rel.metadata, :divorce_month),
        Map.get(rel.metadata, :divorce_year)
      ) %>
    <%= if divorce_info != "" do %>
      <p class="text-xs text-error/60 px-2 flex items-center gap-1">
        <.icon name="hero-arrow-path" class="w-3 h-3" /> Divorced: {divorce_info}
      </p>
    <% end %>
  <% end %>
  <%= if rel.type == "separated" do %>
    <% sep_info =
      format_partial_date(
        Map.get(rel.metadata, :separated_day),
        Map.get(rel.metadata, :separated_month),
        Map.get(rel.metadata, :separated_year)
      ) %>
    <%= if sep_info != "" do %>
      <p class="text-xs text-warning/60 px-2 flex items-center gap-1">
        <.icon name="hero-arrow-path" class="w-3 h-3" /> Separated: {sep_info}
      </p>
    <% end %>
  <% end %>
<% end %>
```

- [ ] **Step 6: Update template — remove convert-to-ex modal**

Delete the entire "Convert to Ex-Partner Modal" block (lines 570-613).

- [ ] **Step 7: Update template — unified edit relationship modal**

First, add `phx-change="validate_edit_relationship"` to the edit modal's `<.form>` tag so the type dropdown dynamically updates visible fields:

```heex
<.form
  for={@edit_relationship_form}
  id="edit-relationship-form"
  phx-submit="save_edit_relationship"
  phx-change="validate_edit_relationship"
>
```

Then replace the partner/ex_partner branches in the edit modal (lines 642-718) with a unified partner form. The `cond` inside the edit modal should have:

```heex
<% @editing_relationship.type == "parent" -> %>
  <%!-- unchanged parent form --%>
  <.input
    field={@edit_relationship_form[:role]}
    type="select"
    label="Role"
    options={[{"Father", "father"}, {"Mother", "mother"}]}
  />
<% Ancestry.Relationships.Relationship.partner_type?(@editing_relationship.type) -> %>
  <.input
    field={@edit_relationship_form[:partner_subtype]}
    type="select"
    label="Relationship Type"
    options={[
      {"Married", "married"},
      {"Relationship", "relationship"},
      {"Divorced", "divorced"},
      {"Separated", "separated"}
    ]}
  />
  <% subtype = Phoenix.HTML.Form.input_value(@edit_relationship_form, :partner_subtype) %>
  <%= if subtype in ~w(married divorced separated) do %>
    <p class="text-sm font-medium text-base-content/60">Marriage Details</p>
    <div class="grid grid-cols-3 gap-3">
      <.input field={@edit_relationship_form[:marriage_day]} type="number" placeholder="Day" label="Day" />
      <.input field={@edit_relationship_form[:marriage_month]} type="number" placeholder="Month" label="Month" />
      <.input field={@edit_relationship_form[:marriage_year]} type="number" placeholder="Year" label="Year" />
    </div>
    <.input field={@edit_relationship_form[:marriage_location]} type="text" label="Location" placeholder="e.g. London, UK" />
  <% end %>
  <%= if subtype == "divorced" do %>
    <p class="text-sm font-medium text-base-content/60 mt-4">Divorce Details</p>
    <div class="grid grid-cols-3 gap-3">
      <.input field={@edit_relationship_form[:divorce_day]} type="number" placeholder="Day" label="Day" />
      <.input field={@edit_relationship_form[:divorce_month]} type="number" placeholder="Month" label="Month" />
      <.input field={@edit_relationship_form[:divorce_year]} type="number" placeholder="Year" label="Year" />
    </div>
  <% end %>
  <%= if subtype == "separated" do %>
    <p class="text-sm font-medium text-base-content/60 mt-4">Separation Details</p>
    <div class="grid grid-cols-3 gap-3">
      <.input field={@edit_relationship_form[:separated_day]} type="number" placeholder="Day" label="Day" />
      <.input field={@edit_relationship_form[:separated_month]} type="number" placeholder="Month" label="Month" />
      <.input field={@edit_relationship_form[:separated_year]} type="number" placeholder="Year" label="Year" />
    </div>
  <% end %>
<% true -> %>
  <p class="text-sm text-base-content/40">
    No editable fields for this relationship type.
  </p>
```

- [ ] **Step 8: Update template — parents' relationship display**

Update the parents marriage display (lines 423-431) to handle all types:

```heex
<%= if @parents_marriage do %>
  <div class="text-sm text-base-content/60 pl-2 border-l-2 border-base-300">
    <span class="font-medium text-base-content/70">
      <%= cond do %>
        <% @parents_marriage.type == "married" -> %>
          Marriage
        <% @parents_marriage.type == "divorced" -> %>
          Divorced
        <% @parents_marriage.type == "separated" -> %>
          Separated
        <% true -> %>
          Relationship
      <% end %>
    </span>
    <% info = format_marriage_info(@parents_marriage.metadata) %>
    <%= if info do %>
      <div>{info}</div>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 9: Rename "Add Spouse" button**

Line 361: Change `Add Spouse` to `Add Partner`.

- [ ] **Step 10: Run tests**

Run: `mix test test/web/live/person_live/relationships_test.exs`
Expected: PASS

- [ ] **Step 11: Commit**

```bash
git add lib/web/live/person_live/show.html.heex test/web/live/person_live/relationships_test.exs
git commit -m "Update person show template for expanded partner relationship types"
```

---

## Task 7: Update Add Relationship Component

**Files:**
- Modify: `lib/web/live/shared/add_relationship_component.ex`
- Test: `test/web/live/family_live/tree_add_relationship_test.exs`

- [ ] **Step 1: Update tree add relationship test**

In `test/web/live/family_live/tree_add_relationship_test.exs`:
- Change `"partner"` → `"married"` in any `create_relationship` calls (line 36)

- [ ] **Step 2: Update `build_relationship_form/2`**

```elixir
defp build_relationship_form(type, selected_person) do
  case type do
    "parent" ->
      role = if selected_person.gender == "male", do: "father", else: "mother"
      to_form(%{"role" => role}, as: :metadata)

    "partner" ->
      to_form(%{"partner_subtype" => "relationship"}, as: :metadata)

    _ ->
      nil
  end
end
```

- [ ] **Step 3: Update `save_relationship` handler for partner type**

In the `"partner"` branch of `handle_event("save_relationship", ...)` (line 142-150):

```elixir
"partner" ->
  metadata_params = Map.get(params, "metadata", %{})
  partner_subtype = Map.get(metadata_params, "partner_subtype", "relationship")
  clean_metadata = Map.delete(metadata_params, "partner_subtype") |> atomize_metadata()

  Relationships.create_relationship(
    person,
    selected,
    partner_subtype,
    clean_metadata
  )
```

- [ ] **Step 4: Update partner metadata form in template**

Replace the partner metadata form section (lines 304-343) with:

```heex
<% @relationship_type == "partner" && @relationship_form -> %>
  <.form
    for={@relationship_form}
    id="add-partner-form"
    phx-target={@myself}
    phx-submit="save_relationship"
    phx-change="validate_partner_form"
  >
    <div class="space-y-4">
      <.input
        field={@relationship_form[:partner_subtype]}
        type="select"
        label="Relationship Type"
        options={[
          {"Married", "married"},
          {"Relationship", "relationship"},
          {"Divorced", "divorced"},
          {"Separated", "separated"}
        ]}
      />
      <% subtype = Phoenix.HTML.Form.input_value(@relationship_form, :partner_subtype) %>
      <%= if subtype in ~w(married divorced separated) do %>
        <p class="text-sm font-medium text-base-content/60">
          Marriage Details (optional)
        </p>
        <div class="grid grid-cols-3 gap-3">
          <.input field={@relationship_form[:marriage_day]} type="number" placeholder="Day" label="Day" />
          <.input field={@relationship_form[:marriage_month]} type="number" placeholder="Month" label="Month" />
          <.input field={@relationship_form[:marriage_year]} type="number" placeholder="Year" label="Year" />
        </div>
        <.input field={@relationship_form[:marriage_location]} type="text" label="Location" placeholder="e.g. London, UK" />
      <% end %>
      <%= if subtype == "divorced" do %>
        <p class="text-sm font-medium text-base-content/60 mt-4">Divorce Details</p>
        <div class="grid grid-cols-3 gap-3">
          <.input field={@relationship_form[:divorce_day]} type="number" placeholder="Day" label="Day" />
          <.input field={@relationship_form[:divorce_month]} type="number" placeholder="Month" label="Month" />
          <.input field={@relationship_form[:divorce_year]} type="number" placeholder="Year" label="Year" />
        </div>
      <% end %>
      <%= if subtype == "separated" do %>
        <p class="text-sm font-medium text-base-content/60 mt-4">Separation Details</p>
        <div class="grid grid-cols-3 gap-3">
          <.input field={@relationship_form[:separated_day]} type="number" placeholder="Day" label="Day" />
          <.input field={@relationship_form[:separated_month]} type="number" placeholder="Month" label="Month" />
          <.input field={@relationship_form[:separated_year]} type="number" placeholder="Year" label="Year" />
        </div>
      <% end %>
      <button type="submit" class="btn btn-primary w-full">Add Partner</button>
    </div>
  </.form>
```

- [ ] **Step 5: Add `validate_partner_form` event handler**

This handles the `phx-change` on the partner form to update the form when the type dropdown changes:

```elixir
def handle_event("validate_partner_form", %{"metadata" => metadata_params}, socket) do
  {:noreply, assign(socket, :relationship_form, to_form(metadata_params, as: :metadata))}
end
```

- [ ] **Step 6: Update `atomize_metadata/1`**

Add `:separated_day`, `:separated_month`, `:separated_year` to the integer parsing whitelist (same change as in show.ex). Also filter out `:partner_subtype`.

- [ ] **Step 7: Update `relationship_title/1`**

```elixir
defp relationship_title("partner"), do: "Add Partner"
```

- [ ] **Step 7b: Add error message for partner-exists validation**

Add a clause to `relationship_error_message/1`:

```elixir
defp relationship_error_message(:partner_relationship_exists),
  do: "This pair already has a partner relationship"
```

- [ ] **Step 8: Run tests**

Run: `mix test test/web/live/family_live/tree_add_relationship_test.exs`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add lib/web/live/shared/add_relationship_component.ex test/web/live/family_live/tree_add_relationship_test.exs
git commit -m "Add partner type dropdown to add relationship component"
```

---

## Task 8: Import & Seeds

**Files:**
- Modify: `lib/ancestry/import/csv/family_echo.ex`
- Modify: `lib/ancestry/import/csv/adapter.ex`
- Modify: `priv/repo/seeds.exs`
- Test: `test/ancestry/import/csv/family_echo_test.exs`
- Test: `test/ancestry/import/csv_test.exs`

- [ ] **Step 1: Update FamilyEcho test**

In `test/ancestry/import/csv/family_echo_test.exs`:
- Line 181: `{:partner, ...}` → `{:relationship, ...}`
- Line 195-197: `{:ex_partner, ...}` → `{:separated, ...}`
- Line 229: `{:partner, ...}` → `{:relationship, ...}`

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/import/csv/family_echo_test.exs`
Expected: FAIL

- [ ] **Step 3: Update FamilyEcho adapter**

In `lib/ancestry/import/csv/family_echo.ex`:
- Line 55: `{:partner, person_eid, @prefix <> partner_id, %{}}` → `{:relationship, person_eid, @prefix <> partner_id, %{}}`
- Line 68: `{:ex_partner, person_eid, @prefix <> ex_id, %{}}` → `{:separated, person_eid, @prefix <> ex_id, %{}}`

- [ ] **Step 4: Update adapter behaviour docs**

In `lib/ancestry/import/csv/adapter.ex`, line 21-23:

```elixir
@doc """
Parse a CSV row map into a list of relationship tuples.

Each tuple is `{type, source_external_id, target_external_id, metadata}` where:
- `type` is an atom like `:parent`, `:married`, `:relationship`, `:divorced`, `:separated`
- `source_external_id` and `target_external_id` are prefixed external IDs
- `metadata` is a map of additional relationship attributes
"""
```

- [ ] **Step 5: Update CSV orchestrator to handle `:partner_relationship_exists` error**

In `lib/ancestry/import/csv.ex`, around line 216 (inside the `true ->` branch of the `cond`), add a handler for the new error atom before the existing `Ecto.Changeset` handler:

```elixir
case Relationships.create_relationship(source, target, Atom.to_string(type), metadata) do
  {:ok, _rel} ->
    %{acc | created: acc.created + 1}

  {:error, :max_parents_reached} ->
    error = "#{type}: max 2 parents for \"#{target_eid}\""
    %{acc | errors: [error | acc.errors]}

  {:error, :partner_relationship_exists} ->
    %{acc | duplicates: acc.duplicates + 1}

  {:error, %Ecto.Changeset{} = changeset} ->
    if duplicate_relationship?(changeset) do
      %{acc | duplicates: acc.duplicates + 1}
    else
      error =
        "#{type} #{source_eid} -> #{target_eid}: #{inspect(format_errors(changeset))}"
      %{acc | errors: [error | acc.errors]}
    end
end
```

- [ ] **Step 6: Update CSV deduplication test**

In `test/ancestry/import/csv_test.exs`, the "deduplicates symmetric partner relationships" test: the dedup will now be caught by `validate_unique_partner_pair` (returning `:partner_relationship_exists`) instead of the DB unique constraint. The test assertions should still pass since both paths increment `duplicates`. Verify by running the test.

- [ ] **Step 7: Run import tests**

Run: `mix test test/ancestry/import/csv/family_echo_test.exs test/ancestry/import/csv_test.exs`
Expected: PASS

- [ ] **Step 8: Update seeds**

In `priv/repo/seeds.exs`, make these replacements:

All `"partner"` type with marriage metadata → `"married"`:
- Lines 66, 173, 181, 189, 207, 359, 367, 375, 383

The one `"ex_partner"` → `"divorced"`:
- Line 197

- [ ] **Step 9: Commit**

```bash
git add lib/ancestry/import/csv/family_echo.ex lib/ancestry/import/csv/adapter.ex lib/ancestry/import/csv.ex priv/repo/seeds.exs test/ancestry/import/csv/family_echo_test.exs
git commit -m "Update FamilyEcho import, CSV orchestrator, and seeds for new partner types"
```

---

## Task 9: DB Migration

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_expand_partner_relationship_types.exs`

- [ ] **Step 1: Generate migration**

Run: `mix ecto.gen.migration expand_partner_relationship_types`

- [ ] **Step 2: Write migration**

```elixir
defmodule Ancestry.Repo.Migrations.ExpandPartnerRelationshipTypes do
  use Ecto.Migration

  def up do
    execute """
    UPDATE relationships
    SET type = 'relationship',
        metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"relationship"')
    WHERE type = 'partner'
    """

    execute """
    UPDATE relationships
    SET type = 'separated',
        metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"separated"')
    WHERE type = 'ex_partner'
    """
  end

  def down do
    execute """
    UPDATE relationships
    SET type = 'partner',
        metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"partner"')
    WHERE type IN ('married', 'relationship')
    """

    execute """
    UPDATE relationships
    SET type = 'ex_partner',
        metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"ex_partner"')
    WHERE type IN ('divorced', 'separated')
    """
  end
end
```

- [ ] **Step 3: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/*expand_partner_relationship_types*
git commit -m "Add data migration to expand partner relationship types"
```

---

## Task 10: Fix Remaining Tests & User Flows

**Files:**
- Modify: `test/ancestry/import/csv_test.exs`
- Modify: `test/user_flows/manage_people_test.exs`

- [ ] **Step 1: Update CSV integration test**

In `test/ancestry/import/csv_test.exs`:
- Line 603 assertion `assert types == ["parent", "partner"]` → `assert types == ["married", "parent"]` (or whatever the updated type would be — check what the test creates)
- Search for any other `"partner"` or `"ex_partner"` strings in the test and update accordingly

- [ ] **Step 2: Update user flow test**

In `test/user_flows/manage_people_test.exs`:
- Line 54: `"partner"` → `"married"` (or `"relationship"` depending on context — this has no marriage metadata so use `"relationship"`)

- [ ] **Step 3: Run all tests**

Run: `mix test`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add test/ancestry/import/csv_test.exs test/user_flows/manage_people_test.exs
git commit -m "Fix remaining test references to old partner type strings"
```

---

## Task 11: Final Verification

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: All checks pass (compile with warnings-as-errors, format, tests)

- [ ] **Step 2: Reset and reseed dev database**

Run: `mix ecto.reset`
Expected: Seeds run successfully with new type strings

- [ ] **Step 3: Manual smoke test (optional)**

Start the dev server: `iex -S mix phx.server`
- Navigate to a family → click a person → verify partner groups show correct titles
- Edit a partner relationship → verify type dropdown appears with all 4 types
- Add a new partner → verify type dropdown defaults to "Relationship"

- [ ] **Step 4: Final commit if any formatting changes**

```bash
git add -A && git commit -m "Final formatting cleanup"
```
