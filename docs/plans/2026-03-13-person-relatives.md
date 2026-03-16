# Person Relatives Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add parent, partner, and ex_partner relationships between persons, with inferred children/siblings, displayed on the Person Show page.

**Architecture:** A single `relationships` table with polymorphic JSONB metadata stores three relationship types. Directional storage for parent (parent→child), symmetric for partner/ex_partner (lower_id, higher_id). The `Ancestry.Relationships` context provides CRUD + query APIs. The existing `PersonLive.Show` page gains a two-column relationships section.

**Tech Stack:** Ecto + PostgreSQL, `polymorphic_embed ~> 5.0`, Phoenix LiveView

---

## Task 1: Add `polymorphic_embed` dependency

**Files:**
- Modify: `mix.exs`

**Step 1: Add the dependency**

In `mix.exs`, add to the `deps` list:

```elixir
{:polymorphic_embed, "~> 5.0"},
```

**Step 2: Fetch deps**

Run: `mix deps.get`
Expected: polymorphic_embed fetched successfully

**Step 3: Commit**

```bash
git add mix.exs mix.lock
git commit -m "Add polymorphic_embed dependency for relationship metadata"
```

---

## Task 2: Create the migration

**Files:**
- Create: `priv/repo/migrations/*_create_relationships.exs` (via `mix ecto.gen.migration`)

**Step 1: Generate the migration file**

Run: `mix ecto.gen.migration create_relationships`

**Step 2: Write the migration**

```elixir
defmodule Ancestry.Repo.Migrations.CreateRelationships do
  use Ecto.Migration

  def change do
    create table(:relationships) do
      add :person_a_id, references(:persons, on_delete: :delete_all), null: false
      add :person_b_id, references(:persons, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:relationships, [:person_a_id, :person_b_id, :type])
    create index(:relationships, [:person_b_id])
  end
end
```

**Step 3: Run the migration**

Run: `mix ecto.migrate`
Expected: migration runs successfully

**Step 4: Commit**

```bash
git add priv/repo/migrations/*_create_relationships.exs
git commit -m "Add relationships table migration"
```

---

## Task 3: Create metadata embedded schemas

**Files:**
- Create: `lib/ancestry/relationships/metadata/partner_metadata.ex`
- Create: `lib/ancestry/relationships/metadata/ex_partner_metadata.ex`
- Create: `lib/ancestry/relationships/metadata/parent_metadata.ex`

**Step 1: Create `PartnerMetadata`**

```elixir
defmodule Ancestry.Relationships.Metadata.PartnerMetadata do
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

**Step 2: Create `ExPartnerMetadata`**

```elixir
defmodule Ancestry.Relationships.Metadata.ExPartnerMetadata do
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

**Step 3: Create `ParentMetadata`**

```elixir
defmodule Ancestry.Relationships.Metadata.ParentMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :role, :string
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, ~w(father mother))
  end
end
```

**Step 4: Verify compilation**

Run: `mix compile`
Expected: compiles without errors

**Step 5: Commit**

```bash
git add lib/ancestry/relationships/metadata/
git commit -m "Add polymorphic metadata schemas for relationships"
```

---

## Task 4: Create the Relationship schema

**Files:**
- Create: `lib/ancestry/relationships/relationship.ex`
- Test: `test/ancestry/relationships_test.exs`

**Step 1: Write the failing test for the changeset**

Create `test/ancestry/relationships_test.exs`:

```elixir
defmodule Ancestry.RelationshipsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Relationships
  alias Ancestry.Relationships.Relationship

  describe "relationship changeset" do
    test "valid parent changeset" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          person_a_id: 1,
          person_b_id: 2,
          type: "parent",
          metadata: %{role: "father"}
        })

      assert changeset.valid?
    end

    test "valid partner changeset with symmetric ID ordering" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          person_a_id: 5,
          person_b_id: 3,
          type: "partner",
          metadata: %{marriage_year: 1920}
        })

      assert changeset.valid?
      # person_a_id should be the lower ID
      assert Ecto.Changeset.get_field(changeset, :person_a_id) == 3
      assert Ecto.Changeset.get_field(changeset, :person_b_id) == 5
    end

    test "rejects invalid type" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          person_a_id: 1,
          person_b_id: 2,
          type: "cousin"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).type
    end

    test "rejects same person on both sides" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          person_a_id: 1,
          person_b_id: 1,
          type: "partner"
        })

      refute changeset.valid?
      assert "cannot be the same person" in errors_on(changeset).person_b_id
    end

    test "parent type requires role in metadata" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          person_a_id: 1,
          person_b_id: 2,
          type: "parent",
          metadata: %{}
        })

      refute changeset.valid?
    end
  end
end
```

**Step 2: Run the test to verify it fails**

Run: `mix test test/ancestry/relationships_test.exs`
Expected: FAIL — `Relationship` module not found

**Step 3: Write the Relationship schema**

Create `lib/ancestry/relationships/relationship.ex`:

```elixir
defmodule Ancestry.Relationships.Relationship do
  use Ecto.Schema
  import Ecto.Changeset
  import PolymorphicEmbed

  schema "relationships" do
    field :person_a_id, :integer
    field :person_b_id, :integer
    field :type, :string

    polymorphic_embeds_one :metadata,
      types: [
        parent: Ancestry.Relationships.Metadata.ParentMetadata,
        partner: Ancestry.Relationships.Metadata.PartnerMetadata,
        ex_partner: Ancestry.Relationships.Metadata.ExPartnerMetadata
      ],
      type_field_name: :__type__,
      on_type_not_found: :raise,
      on_replace: :update

    timestamps()
  end

  @valid_types ~w(parent partner ex_partner)

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:person_a_id, :person_b_id, :type])
    |> validate_required([:person_a_id, :person_b_id, :type])
    |> validate_inclusion(:type, @valid_types)
    |> validate_different_persons()
    |> maybe_order_symmetric_ids()
    |> cast_polymorphic_embed(:metadata, required: false)
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

    if type in ~w(partner ex_partner) && a && b && a > b do
      changeset
      |> put_change(:person_a_id, b)
      |> put_change(:person_b_id, a)
    else
      changeset
    end
  end
end
```

**Step 4: Run the test to verify it passes**

Run: `mix test test/ancestry/relationships_test.exs`
Expected: all tests PASS

**Step 5: Commit**

```bash
git add lib/ancestry/relationships/relationship.ex test/ancestry/relationships_test.exs
git commit -m "Add Relationship schema with polymorphic metadata"
```

---

## Task 5: Create the Relationships context — CRUD

**Files:**
- Create: `lib/ancestry/relationships.ex`
- Modify: `test/ancestry/relationships_test.exs`

**Step 1: Write failing tests for CRUD operations**

Add to `test/ancestry/relationships_test.exs`:

```elixir
  describe "create_relationship/4" do
    test "creates a parent relationship" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, child} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      assert {:ok, rel} =
               Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      assert rel.person_a_id == parent.id
      assert rel.person_b_id == child.id
      assert rel.type == "parent"
    end

    test "creates a partner relationship with symmetric ordering" do
      family = family_fixture()
      {:ok, person_a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, person_b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      # Pass higher ID first — should be reordered
      assert {:ok, rel} =
               Relationships.create_relationship(person_b, person_a, "partner", %{
                 marriage_year: 2020
               })

      assert rel.person_a_id == min(person_a.id, person_b.id)
      assert rel.person_b_id == max(person_a.id, person_b.id)
    end

    test "prevents duplicate relationships" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, child} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      assert {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
      assert {:error, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
    end

    test "enforces max 2 parents per child" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "John", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Jane", surname: "D"})
      {:ok, extra} = People.create_person(family, %{given_name: "Extra", surname: "D"})
      {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})

      assert {:ok, _} = Relationships.create_relationship(father, child, "parent", %{role: "father"})
      assert {:ok, _} = Relationships.create_relationship(mother, child, "parent", %{role: "mother"})
      assert {:error, _} = Relationships.create_relationship(extra, child, "parent", %{role: "father"})
    end
  end

  describe "delete_relationship/1" do
    test "deletes a relationship" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, child} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      {:ok, rel} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      assert {:ok, _} = Relationships.delete_relationship(rel)
      assert Relationships.get_parents(child.id) == []
    end
  end

  describe "update_relationship/2" do
    test "updates metadata" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})
      {:ok, rel} = Relationships.create_relationship(a, b, "partner", %{marriage_year: 2020})

      assert {:ok, updated} =
               Relationships.update_relationship(rel, %{metadata: %{marriage_year: 2021}})

      assert updated.metadata.marriage_year == 2021
    end
  end

  describe "convert_to_ex_partner/2" do
    test "converts partner to ex_partner carrying marriage metadata" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, rel} =
        Relationships.create_relationship(a, b, "partner", %{
          marriage_year: 2020,
          marriage_location: "Paris"
        })

      assert {:ok, ex_rel} =
               Relationships.convert_to_ex_partner(rel, %{divorce_year: 2023})

      assert ex_rel.type == "ex_partner"
      assert ex_rel.metadata.marriage_year == 2020
      assert ex_rel.metadata.marriage_location == "Paris"
      assert ex_rel.metadata.divorce_year == 2023

      # Original partner relationship should be gone
      assert Relationships.get_partners(a.id) == []
    end
  end

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Ancestry.Families.create_family()

    family
  end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/relationships_test.exs`
Expected: FAIL — `Relationships` module not found

**Step 3: Write the context module**

Create `lib/ancestry/relationships.ex`:

```elixir
defmodule Ancestry.Relationships do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.Relationships.Relationship

  def create_relationship(person_a, person_b, type, metadata_attrs \\ %{}) do
    attrs = %{
      person_a_id: person_a.id,
      person_b_id: person_b.id,
      type: type,
      metadata: metadata_attrs
    }

    with :ok <- validate_parent_limit(person_b.id, type) do
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

  def convert_to_ex_partner(%Relationship{type: "partner"} = rel, divorce_attrs) do
    ex_metadata =
      %{
        marriage_day: rel.metadata.marriage_day,
        marriage_month: rel.metadata.marriage_month,
        marriage_year: rel.metadata.marriage_year,
        marriage_location: rel.metadata.marriage_location
      }
      |> Map.merge(divorce_attrs)

    Repo.transaction(fn ->
      case Repo.delete(rel) do
        {:ok, _} ->
          %Relationship{}
          |> Relationship.changeset(%{
            person_a_id: rel.person_a_id,
            person_b_id: rel.person_b_id,
            type: "ex_partner",
            metadata: ex_metadata
          })
          |> Repo.insert!()

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def change_relationship(%Relationship{} = rel, attrs \\ %{}) do
    Relationship.changeset(rel, attrs)
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
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/relationships_test.exs`
Expected: all tests PASS

**Step 5: Commit**

```bash
git add lib/ancestry/relationships.ex test/ancestry/relationships_test.exs
git commit -m "Add Relationships context with CRUD and convert-to-ex"
```

---

## Task 6: Add query functions to the Relationships context

**Files:**
- Modify: `lib/ancestry/relationships.ex`
- Modify: `test/ancestry/relationships_test.exs`

**Step 1: Write failing tests for queries**

Add to `test/ancestry/relationships_test.exs`:

```elixir
  alias Ancestry.People

  describe "get_parents/1" do
    test "returns parents of a person" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "John", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Jane", surname: "D"})
      {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

      parents = Relationships.get_parents(child.id)
      assert length(parents) == 2
      parent_ids = Enum.map(parents, fn {person, _rel} -> person.id end)
      assert father.id in parent_ids
      assert mother.id in parent_ids
    end
  end

  describe "get_children/1" do
    test "returns children of a person" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "John", surname: "D"})
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})

      {:ok, _} = Relationships.create_relationship(parent, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(parent, child2, "parent", %{role: "father"})

      children = Relationships.get_children(parent.id)
      assert length(children) == 2
      child_ids = Enum.map(children, & &1.id)
      assert child1.id in child_ids
      assert child2.id in child_ids
    end
  end

  describe "get_partners/1" do
    test "returns current partners" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, _} = Relationships.create_relationship(a, b, "partner", %{marriage_year: 2020})

      partners = Relationships.get_partners(a.id)
      assert length(partners) == 1
      assert {partner, _rel} = hd(partners)
      assert partner.id == b.id

      # Also works from the other side
      partners_b = Relationships.get_partners(b.id)
      assert length(partners_b) == 1
      assert {partner_b, _rel} = hd(partners_b)
      assert partner_b.id == a.id
    end
  end

  describe "get_ex_partners/1" do
    test "returns ex-partners" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, _} = Relationships.create_relationship(a, b, "ex_partner", %{
        marriage_year: 2010,
        divorce_year: 2015
      })

      exes = Relationships.get_ex_partners(a.id)
      assert length(exes) == 1
      assert {ex, _rel} = hd(exes)
      assert ex.id == b.id
    end
  end

  describe "get_siblings/1" do
    test "returns full siblings sharing both parents" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "D"})
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child1, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child2, "parent", %{role: "mother"})

      siblings = Relationships.get_siblings(child1.id)
      assert length(siblings) == 1
      assert {sibling, parent_a_id, parent_b_id} = hd(siblings)
      assert sibling.id == child2.id
      assert parent_a_id in [father.id, mother.id]
      assert parent_b_id in [father.id, mother.id]
    end

    test "returns half-siblings sharing one parent" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother1} = People.create_person(family, %{given_name: "Mom1", surname: "D"})
      {:ok, mother2} = People.create_person(family, %{given_name: "Mom2", surname: "D"})
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother1, child1, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother2, child2, "parent", %{role: "mother"})

      siblings = Relationships.get_siblings(child1.id)
      assert length(siblings) == 1
      assert {sibling, shared_parent_id} = hd(siblings)
      assert sibling.id == child2.id
      assert shared_parent_id == father.id
    end

    test "returns empty list when no shared parents" do
      family = family_fixture()
      {:ok, child} = People.create_person(family, %{given_name: "Lonely", surname: "Kid"})
      assert Relationships.get_siblings(child.id) == []
    end
  end

  describe "get_children_of_pair/2" do
    test "returns children shared by two specific parents" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "D"})
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})
      {:ok, solo_child} = People.create_person(family, %{given_name: "Solo", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child1, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child2, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(father, solo_child, "parent", %{role: "father"})

      shared = Relationships.get_children_of_pair(father.id, mother.id)
      assert length(shared) == 2
      ids = Enum.map(shared, & &1.id)
      assert child1.id in ids
      assert child2.id in ids
      refute solo_child.id in ids
    end
  end

  describe "get_solo_children/1" do
    test "returns children with only one parent (this person)" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "D"})
      {:ok, paired_child} = People.create_person(family, %{given_name: "Paired", surname: "D"})
      {:ok, solo_child} = People.create_person(family, %{given_name: "Solo", surname: "D"})

      {:ok, _} = Relationships.create_relationship(parent, paired_child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, paired_child, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(parent, solo_child, "parent", %{role: "father"})

      solo = Relationships.get_solo_children(parent.id)
      assert length(solo) == 1
      assert hd(solo).id == solo_child.id
    end
  end
```

**Step 2: Run the tests to verify they fail**

Run: `mix test test/ancestry/relationships_test.exs`
Expected: FAIL — functions not defined

**Step 3: Add query functions to the context**

Add to `lib/ancestry/relationships.ex`:

```elixir
  alias Ancestry.People.Person

  def get_parents(person_id) do
    Repo.all(
      from r in Relationship,
        join: p in Person, on: p.id == r.person_a_id,
        where: r.person_b_id == ^person_id and r.type == "parent",
        select: {p, r}
    )
  end

  def get_children(person_id) do
    Repo.all(
      from r in Relationship,
        join: p in Person, on: p.id == r.person_b_id,
        where: r.person_a_id == ^person_id and r.type == "parent",
        select: p
    )
  end

  def get_partners(person_id) do
    Repo.all(
      from r in Relationship,
        join: p in Person, on: (p.id == r.person_a_id and r.person_b_id == ^person_id) or
                               (p.id == r.person_b_id and r.person_a_id == ^person_id),
        where: r.type == "partner",
        where: (r.person_a_id == ^person_id or r.person_b_id == ^person_id),
        where: p.id != ^person_id,
        select: {p, r}
    )
  end

  def get_ex_partners(person_id) do
    Repo.all(
      from r in Relationship,
        join: p in Person, on: (p.id == r.person_a_id and r.person_b_id == ^person_id) or
                               (p.id == r.person_b_id and r.person_a_id == ^person_id),
        where: r.type == "ex_partner",
        where: (r.person_a_id == ^person_id or r.person_b_id == ^person_id),
        where: p.id != ^person_id,
        select: {p, r}
    )
  end

  def get_children_of_pair(parent_a_id, parent_b_id) do
    Repo.all(
      from r1 in Relationship,
        join: r2 in Relationship,
          on: r1.person_b_id == r2.person_b_id and r1.id != r2.id,
        join: p in Person, on: p.id == r1.person_b_id,
        where: r1.type == "parent" and r2.type == "parent",
        where: r1.person_a_id == ^parent_a_id and r2.person_a_id == ^parent_b_id,
        select: p
    )
  end

  def get_solo_children(person_id) do
    # Children of this person that have no other parent
    children_with_two_parents =
      from r1 in Relationship,
        join: r2 in Relationship,
          on: r1.person_b_id == r2.person_b_id and r1.id != r2.id,
        where: r1.type == "parent" and r2.type == "parent",
        where: r1.person_a_id == ^person_id,
        select: r1.person_b_id

    Repo.all(
      from r in Relationship,
        join: p in Person, on: p.id == r.person_b_id,
        where: r.person_a_id == ^person_id and r.type == "parent",
        where: r.person_b_id not in subquery(children_with_two_parents),
        select: p
    )
  end

  def get_siblings(person_id) do
    # Find parents of this person
    parent_ids =
      Repo.all(
        from r in Relationship,
          where: r.person_b_id == ^person_id and r.type == "parent",
          select: r.person_a_id
      )

    case parent_ids do
      [] ->
        []

      [single_parent] ->
        # All children of that parent except this person = half-siblings
        Repo.all(
          from r in Relationship,
            join: p in Person, on: p.id == r.person_b_id,
            where: r.person_a_id == ^single_parent and r.type == "parent",
            where: r.person_b_id != ^person_id,
            select: {p, ^single_parent}
        )

      [parent1, parent2] ->
        # Check each sibling: do they share both parents or just one?
        other_children_of_p1 =
          from r in Relationship,
            where: r.person_a_id == ^parent1 and r.type == "parent" and r.person_b_id != ^person_id,
            select: r.person_b_id

        other_children_of_p2 =
          from r in Relationship,
            where: r.person_a_id == ^parent2 and r.type == "parent" and r.person_b_id != ^person_id,
            select: r.person_b_id

        full_sibling_ids = Repo.all(
          from c1 in subquery(other_children_of_p1),
            join: c2 in subquery(other_children_of_p2), on: c1.person_b_id == c2.person_b_id,
            select: c1.person_b_id
        )

        half_from_p1 = Repo.all(
          from r in Relationship,
            join: p in Person, on: p.id == r.person_b_id,
            where: r.person_a_id == ^parent1 and r.type == "parent",
            where: r.person_b_id != ^person_id,
            where: r.person_b_id not in ^full_sibling_ids,
            select: {p, ^parent1}
        )

        half_from_p2 = Repo.all(
          from r in Relationship,
            join: p in Person, on: p.id == r.person_b_id,
            where: r.person_a_id == ^parent2 and r.type == "parent",
            where: r.person_b_id != ^person_id,
            where: r.person_b_id not in ^full_sibling_ids,
            select: {p, ^parent2}
        )

        full_siblings = Repo.all(
          from p in Person,
            where: p.id in ^full_sibling_ids,
            select: {p, ^parent1, ^parent2}
        )

        full_siblings ++ half_from_p1 ++ half_from_p2
    end
  end
```

> **Note:** The `get_siblings/1` function is the most complex query. The implementation may need adjustment during testing — the key contract is the return types: `{person, parent_a_id, parent_b_id}` for full siblings and `{person, shared_parent_id}` for half-siblings.

**Step 4: Run the tests**

Run: `mix test test/ancestry/relationships_test.exs`
Expected: all tests PASS

**Step 5: Commit**

```bash
git add lib/ancestry/relationships.ex test/ancestry/relationships_test.exs
git commit -m "Add relationship query functions with sibling inference"
```

---

## Task 7: Add search within family for relationship picker

**Files:**
- Modify: `lib/ancestry/people.ex`
- Modify: `test/ancestry/people_test.exs`

**Step 1: Write failing test**

Add to `test/ancestry/people_test.exs`:

```elixir
  describe "search_family_members/3" do
    test "searches people within a family by name, excluding a specific person" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "Wonderland"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "Builder"})

      results = People.search_family_members("ali", family.id, alice.id)
      assert results == []

      results = People.search_family_members("bob", family.id, alice.id)
      assert length(results) == 1
      assert hd(results).id == bob.id
    end
  end
```

**Step 2: Run to verify it fails**

Run: `mix test test/ancestry/people_test.exs --only describe:"search_family_members/3"`
Expected: FAIL

**Step 3: Add the function**

Add to `lib/ancestry/people.ex`:

```elixir
  def search_family_members(query, family_id, exclude_person_id) do
    escaped =
      query
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    like = "%#{escaped}%"

    Repo.all(
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id,
        where: fm.family_id == ^family_id,
        where: p.id != ^exclude_person_id,
        where:
          ilike(p.given_name, ^like) or
            ilike(p.surname, ^like) or
            ilike(p.nickname, ^like),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20
    )
  end
```

**Step 4: Run to verify it passes**

Run: `mix test test/ancestry/people_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "Add search_family_members for relationship picker"
```

---

## Task 8: Add relationships data loading to PersonLive.Show

**Files:**
- Modify: `lib/web/live/person_live/show.ex`

**Step 1: Update mount to load relationship data**

Add `alias Ancestry.Relationships` to the top of the module.

In `mount/3`, after the existing assigns, add a helper call to load all relationship data:

```elixir
|> load_relationships(person)
```

Add the helper:

```elixir
  defp load_relationships(socket, person) do
    parents = Relationships.get_parents(person.id)
    partners = Relationships.get_partners(person.id)
    ex_partners = Relationships.get_ex_partners(person.id)
    siblings = Relationships.get_siblings(person.id)
    solo_children = Relationships.get_solo_children(person.id)

    # For each partner/ex_partner, load their shared children
    partner_children =
      Enum.map(partners ++ ex_partners, fn {partner, rel} ->
        children = Relationships.get_children_of_pair(person.id, partner.id)
        {partner, rel, children}
      end)

    socket
    |> assign(:parents, parents)
    |> assign(:partner_children, partner_children)
    |> assign(:siblings, siblings)
    |> assign(:solo_children, solo_children)
    |> assign(:adding_relationship, nil)
    |> assign(:search_query, "")
    |> assign(:search_results, [])
    |> assign(:selected_person, nil)
    |> assign(:relationship_form, nil)
  end
```

**Step 2: Verify it compiles**

Run: `mix compile`
Expected: compiles without errors

**Step 3: Commit**

```bash
git add lib/web/live/person_live/show.ex
git commit -m "Load relationship data in PersonLive.Show mount"
```

---

## Task 9: Add relationship display to the Person Show template

**Files:**
- Modify: `lib/web/live/person_live/show.html.heex`

This is the largest UI task. Add the two-column relationships section below the existing person details (after the `</div>` closing the max-w-4xl detail view, before the modals, inside the `else` branch).

**Step 1: Add the relationships section to the template**

Insert after line 300 (`</div>` closing the detail view `max-w-4xl`) and before line 301 (`<% end %>`):

```heex
    <%!-- Relationships Section --%>
    <div class="max-w-6xl mx-auto mt-12">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <%!-- Left column: Spouses and Children --%>
        <div>
          <h2 class="text-xl font-bold text-base-content mb-6">Spouses and Children</h2>

          <%= for {partner, rel, children} <- @partner_children do %>
            <div class="mb-6 border border-base-300 rounded-xl p-4">
              <%!-- Current person card (highlighted) --%>
              <.person_card person={@person} highlighted={true} family={@family} />

              <%!-- Partner/Ex card --%>
              <.person_card person={partner} highlighted={false} family={@family} />

              <%!-- Marriage info --%>
              <div class="mt-3 flex items-center justify-between text-sm text-base-content/60">
                <div>
                  <span class="font-medium text-base-content">
                    <%= if rel.type == "ex_partner" do %>
                      Marriage (divorced)
                    <% else %>
                      Marriage
                    <% end %>
                  </span>
                  <div>
                    {format_partial_date(
                      rel.metadata.marriage_day,
                      rel.metadata.marriage_month,
                      rel.metadata.marriage_year
                    )}
                    <%= if rel.metadata.marriage_location do %>
                      <span class="ml-1">{rel.metadata.marriage_location}</span>
                    <% end %>
                  </div>
                  <%= if rel.type == "ex_partner" do %>
                    <div class="text-error/70">
                      Divorced: {format_partial_date(
                        rel.metadata.divorce_day,
                        rel.metadata.divorce_month,
                        rel.metadata.divorce_year
                      )}
                    </div>
                  <% end %>
                </div>
                <button
                  phx-click="edit_relationship"
                  phx-value-id={rel.id}
                  class="p-1.5 rounded-lg text-base-content/30 hover:text-base-content hover:bg-base-200 transition-all"
                >
                  <.icon name="hero-pencil" class="w-4 h-4" />
                </button>
              </div>

              <%!-- Children section --%>
              <details class="mt-4" open>
                <summary class="cursor-pointer font-medium text-base-content text-sm">
                  Children ({length(children)})
                </summary>
                <div class="mt-2 space-y-2">
                  <%= for child <- children do %>
                    <.person_card person={child} highlighted={false} family={@family} />
                  <% end %>
                  <button
                    phx-click="add_relationship"
                    phx-value-type="child"
                    phx-value-partner-id={partner.id}
                    class="w-full text-left text-sm text-primary hover:text-primary/80 font-medium py-2 transition-colors"
                  >
                    + Add Child
                  </button>
                </div>
              </details>

              <%!-- Convert to ex button for partners --%>
              <%= if rel.type == "partner" do %>
                <div class="mt-3 pt-3 border-t border-base-300">
                  <button
                    phx-click="convert_to_ex"
                    phx-value-id={rel.id}
                    class="text-xs text-base-content/40 hover:text-error transition-colors"
                  >
                    Mark as ex-partner
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>

          <%!-- Solo children (unknown other parent) --%>
          <%= if @solo_children != [] do %>
            <div class="mb-6 border border-base-300 rounded-xl p-4">
              <details open>
                <summary class="cursor-pointer font-medium text-base-content text-sm">
                  Children with unknown parent ({length(@solo_children)})
                </summary>
                <div class="mt-2 space-y-2">
                  <%= for child <- @solo_children do %>
                    <.person_card person={child} highlighted={false} family={@family} />
                  <% end %>
                </div>
              </details>
            </div>
          <% end %>

          <button
            phx-click="add_relationship"
            phx-value-type="partner"
            class="text-sm text-primary hover:text-primary/80 font-medium transition-colors"
          >
            + Add Spouse
          </button>
          <br />
          <button
            phx-click="add_relationship"
            phx-value-type="child_solo"
            class="text-sm text-primary hover:text-primary/80 font-medium mt-2 transition-colors"
          >
            + Add Child with Unknown Parent
          </button>
        </div>

        <%!-- Right column: Parents and Siblings --%>
        <div>
          <h2 class="text-xl font-bold text-base-content mb-6">Parents and Siblings</h2>

          <div class="space-y-3 mb-6">
            <%= for {parent, rel} <- @parents do %>
              <div class="flex items-center gap-3">
                <.person_card person={parent} highlighted={false} family={@family} />
                <span class="text-xs text-base-content/40 uppercase">
                  {rel.metadata.role}
                </span>
              </div>
            <% end %>

            <%= if length(@parents) < 2 do %>
              <button
                phx-click="add_relationship"
                phx-value-type="parent"
                class="text-sm text-primary hover:text-primary/80 font-medium transition-colors"
              >
                + Add Parent
              </button>
            <% end %>
          </div>

          <%!-- Siblings --%>
          <%= if @siblings != [] do %>
            <details open>
              <summary class="cursor-pointer font-medium text-base-content text-sm mb-2">
                Siblings ({length(@siblings)})
              </summary>
              <div class="space-y-2">
                <%!-- Current person highlighted --%>
                <.person_card person={@person} highlighted={true} family={@family} />
                <%= for sibling_entry <- @siblings do %>
                  <%
                    {sibling, _rest} = case sibling_entry do
                      {s, _parent_a, _parent_b} -> {s, :full}
                      {s, _parent} -> {s, :half}
                    end
                    label = case sibling_entry do
                      {_, _, _} -> nil
                      {_, _} -> "Half-sibling"
                    end
                  %>
                  <div>
                    <.person_card person={sibling} highlighted={false} family={@family} />
                    <%= if label do %>
                      <span class="text-xs text-base-content/40 ml-2">{label}</span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </details>
          <% end %>
        </div>
      </div>
    </div>
```

**Step 2: Add the `person_card` function component**

Add to `lib/web/live/person_live/show.ex`:

```elixir
  defp person_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/families/#{@family.id}/members/#{@person.id}"}
      class={[
        "flex items-center gap-3 p-2 rounded-lg transition-colors",
        @highlighted && "bg-primary/10 border border-primary/20",
        !@highlighted && "hover:bg-base-200"
      ]}
    >
      <div class={[
        "w-10 h-10 rounded-full flex-shrink-0 flex items-center justify-center overflow-hidden",
        "border-l-4",
        @person.gender == "male" && "border-l-blue-400 bg-blue-50",
        @person.gender == "female" && "border-l-pink-400 bg-pink-50",
        @person.gender not in ["male", "female"] && "border-l-base-300 bg-base-200"
      ]}>
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Ancestry.People.Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <.icon name="hero-user" class="w-5 h-5 text-base-content/20" />
        <% end %>
      </div>
      <div class="min-w-0 flex-1">
        <p class="font-medium text-sm text-base-content truncate">
          {Ancestry.People.Person.display_name(@person)}
        </p>
        <p class="text-xs text-base-content/50">
          <%= if @person.birth_year do %>
            {@person.birth_year}<%= if @person.death_year do %>–{@person.death_year}<% end %>
          <% end %>
        </p>
      </div>
    </.link>
    """
  end
```

**Step 3: Verify it compiles**

Run: `mix compile`
Expected: compiles without errors

**Step 4: Commit**

```bash
git add lib/web/live/person_live/show.ex lib/web/live/person_live/show.html.heex
git commit -m "Add relationships display to Person Show page"
```

---

## Task 10: Add relationship event handlers (add, search, create)

**Files:**
- Modify: `lib/web/live/person_live/show.ex`

**Step 1: Add event handlers for the "add relationship" flow**

```elixir
  # Opens the add-relationship flow for a given type
  def handle_event("add_relationship", %{"type" => type} = params, socket) do
    partner_id = Map.get(params, "partner-id")

    {:noreply,
     socket
     |> assign(:adding_relationship, type)
     |> assign(:adding_partner_id, partner_id)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:selected_person, nil)
     |> assign(:relationship_form, nil)}
  end

  def handle_event("cancel_add_relationship", _, socket) do
    {:noreply,
     socket
     |> assign(:adding_relationship, nil)
     |> assign(:search_results, [])
     |> assign(:selected_person, nil)
     |> assign(:relationship_form, nil)}
  end

  def handle_event("search_members", %{"query" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        People.search_family_members(query, socket.assigns.family.id, socket.assigns.person.id)
      else
        []
      end

    {:noreply, socket |> assign(:search_query, query) |> assign(:search_results, results)}
  end

  def handle_event("select_person", %{"id" => id}, socket) do
    selected = People.get_person!(id)
    type = socket.assigns.adding_relationship

    form =
      case type do
        "parent" ->
          to_form(%{"role" => ""}, as: :metadata)

        t when t in ["partner", "ex_partner"] ->
          to_form(%{}, as: :metadata)

        "child" ->
          nil

        "child_solo" ->
          nil
      end

    {:noreply,
     socket
     |> assign(:selected_person, selected)
     |> assign(:relationship_form, form)}
  end

  def handle_event("save_relationship", params, socket) do
    person = socket.assigns.person
    selected = socket.assigns.selected_person
    type = socket.assigns.adding_relationship

    result =
      case type do
        "parent" ->
          metadata = Map.get(params, "metadata", %{})
          Relationships.create_relationship(selected, person, "parent", metadata)

        "partner" ->
          metadata = Map.get(params, "metadata", %{})
          Relationships.create_relationship(person, selected, "partner", metadata)

        "ex_partner" ->
          metadata = Map.get(params, "metadata", %{})
          Relationships.create_relationship(person, selected, "ex_partner", metadata)

        "child" ->
          Relationships.create_relationship(person, selected, "parent", %{
            role: if(person.gender == "female", do: "mother", else: "father")
          })

        "child_solo" ->
          Relationships.create_relationship(person, selected, "parent", %{
            role: if(person.gender == "female", do: "mother", else: "father")
          })
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:adding_relationship, nil)
         |> load_relationships(person)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, relationship_error_message(reason))}
    end
  end

  def handle_event("convert_to_ex", %{"id" => id}, socket) do
    rel = Repo.get!(Relationship, String.to_integer(id))

    {:noreply,
     socket
     |> assign(:converting_to_ex, rel)
     |> assign(:ex_form, to_form(%{}, as: :divorce))}
  end

  def handle_event("save_convert_to_ex", %{"divorce" => divorce_params}, socket) do
    rel = socket.assigns.converting_to_ex

    case Relationships.convert_to_ex_partner(rel, divorce_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:converting_to_ex, nil)
         |> load_relationships(socket.assigns.person)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to convert relationship")}
    end
  end

  def handle_event("edit_relationship", %{"id" => id}, socket) do
    rel = Repo.get!(Relationship, String.to_integer(id))
    form = to_form(Relationships.change_relationship(rel))

    {:noreply,
     socket
     |> assign(:editing_relationship, rel)
     |> assign(:edit_relationship_form, form)}
  end

  def handle_event("cancel_edit_relationship", _, socket) do
    {:noreply, assign(socket, :editing_relationship, nil)}
  end

  def handle_event("save_edit_relationship", %{"relationship" => params}, socket) do
    rel = socket.assigns.editing_relationship

    case Relationships.update_relationship(rel, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:editing_relationship, nil)
         |> load_relationships(socket.assigns.person)}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_relationship_form, to_form(changeset))}
    end
  end

  def handle_event("delete_relationship", %{"id" => id}, socket) do
    rel = Repo.get!(Relationship, String.to_integer(id))
    {:ok, _} = Relationships.delete_relationship(rel)

    {:noreply, load_relationships(socket, socket.assigns.person)}
  end

  defp relationship_error_message(:max_parents_reached), do: "This person already has 2 parents"
  defp relationship_error_message(%Ecto.Changeset{}), do: "Invalid relationship data"
  defp relationship_error_message(_), do: "Failed to create relationship"
```

**Step 2: Add necessary aliases at the top of the module**

```elixir
alias Ancestry.Relationships
alias Ancestry.Relationships.Relationship
alias Ancestry.Repo
```

**Step 3: Initialize additional assigns in mount**

Add to `load_relationships/2`:

```elixir
|> assign_new(:converting_to_ex, fn -> nil end)
|> assign_new(:ex_form, fn -> nil end)
|> assign_new(:editing_relationship, fn -> nil end)
|> assign_new(:edit_relationship_form, fn -> nil end)
|> assign_new(:adding_partner_id, fn -> nil end)
```

**Step 4: Verify it compiles**

Run: `mix compile`
Expected: compiles without errors

**Step 5: Commit**

```bash
git add lib/web/live/person_live/show.ex
git commit -m "Add relationship event handlers to PersonLive.Show"
```

---

## Task 11: Add relationship modal/forms to template

**Files:**
- Modify: `lib/web/live/person_live/show.html.heex`

**Step 1: Add the "Add Relationship" modal**

Add before the closing `</Layouts.app>`:

```heex
  <%!-- Add Relationship Modal --%>
  <%= if @adding_relationship do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_add_relationship">
      </div>
      <div
        id="add-relationship-modal"
        class="relative card bg-base-100 shadow-2xl w-full max-w-lg mx-4 p-6"
      >
        <h2 class="text-lg font-bold text-base-content mb-4">
          <%= case @adding_relationship do %>
            <% "parent" -> %>
              Add Parent
            <% "partner" -> %>
              Add Spouse
            <% "child" -> %>
              Add Child
            <% "child_solo" -> %>
              Add Child
            <% "ex_partner" -> %>
              Add Ex-Partner
          <% end %>
        </h2>

        <%= if @selected_person == nil do %>
          <%!-- Search step --%>
          <div>
            <input
              id="relationship-search-input"
              type="text"
              placeholder="Search family members by name..."
              value={@search_query}
              phx-keyup="search_members"
              phx-debounce="300"
              class="input input-bordered w-full mb-3"
              autofocus
            />
            <%= if @search_results != [] do %>
              <div class="max-h-60 overflow-y-auto space-y-1">
                <%= for result <- @search_results do %>
                  <button
                    phx-click="select_person"
                    phx-value-id={result.id}
                    class="w-full text-left"
                  >
                    <.person_card person={result} highlighted={false} family={@family} />
                  </button>
                <% end %>
              </div>
            <% else %>
              <%= if String.length(@search_query) >= 2 do %>
                <p class="text-sm text-base-content/50">No results found</p>
              <% end %>
            <% end %>
          </div>
        <% else %>
          <%!-- Metadata step --%>
          <div class="mb-4">
            <.person_card person={@selected_person} highlighted={true} family={@family} />
          </div>

          <.form
            for={@relationship_form || to_form(%{}, as: :metadata)}
            id="relationship-form"
            phx-submit="save_relationship"
          >
            <%= case @adding_relationship do %>
              <% "parent" -> %>
                <.input
                  field={@relationship_form[:role]}
                  type="select"
                  label="Role"
                  prompt="Select role..."
                  options={[{"Father", "father"}, {"Mother", "mother"}]}
                />
              <% t when t in ["partner", "ex_partner"] -> %>
                <div class="space-y-3">
                  <label class="block text-sm font-medium text-base-content">Marriage date</label>
                  <div class="grid grid-cols-3 gap-3">
                    <.input field={@relationship_form[:marriage_day]} type="number" placeholder="Day" />
                    <.input
                      field={@relationship_form[:marriage_month]}
                      type="number"
                      placeholder="Month"
                    />
                    <.input
                      field={@relationship_form[:marriage_year]}
                      type="number"
                      placeholder="Year"
                    />
                  </div>
                  <.input
                    field={@relationship_form[:marriage_location]}
                    type="text"
                    label="Location"
                    placeholder="e.g. Paris, France"
                  />
                </div>
              <% _ -> %>
                <%!-- child / child_solo: no extra metadata needed --%>
            <% end %>

            <div class="flex gap-3 mt-6">
              <button type="submit" class="btn btn-primary flex-1">Save</button>
              <button
                type="button"
                phx-click="cancel_add_relationship"
                class="btn btn-ghost flex-1"
              >
                Cancel
              </button>
            </div>
          </.form>
        <% end %>
      </div>
    </div>
  <% end %>

  <%!-- Convert to Ex Modal --%>
  <%= if @converting_to_ex do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm"></div>
      <div
        id="convert-to-ex-modal"
        class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-6"
      >
        <h2 class="text-lg font-bold text-base-content mb-4">Mark as Ex-Partner</h2>
        <.form for={@ex_form} id="convert-to-ex-form" phx-submit="save_convert_to_ex">
          <label class="block text-sm font-medium text-base-content mb-2">Divorce date</label>
          <div class="grid grid-cols-3 gap-3">
            <.input field={@ex_form[:divorce_day]} type="number" placeholder="Day" />
            <.input field={@ex_form[:divorce_month]} type="number" placeholder="Month" />
            <.input field={@ex_form[:divorce_year]} type="number" placeholder="Year" />
          </div>
          <div class="flex gap-3 mt-6">
            <button type="submit" class="btn btn-error flex-1">Confirm</button>
            <button
              type="button"
              phx-click="cancel_add_relationship"
              class="btn btn-ghost flex-1"
            >
              Cancel
            </button>
          </div>
        </.form>
      </div>
    </div>
  <% end %>
```

**Step 2: Verify it compiles**

Run: `mix compile`
Expected: compiles without errors

**Step 3: Commit**

```bash
git add lib/web/live/person_live/show.html.heex
git commit -m "Add relationship modals and forms to Person Show template"
```

---

## Task 12: Add LiveView tests for relationships

**Files:**
- Create: `test/web/live/person_live/relationships_test.exs`

**Step 1: Write the tests**

```elixir
defmodule Web.PersonLive.RelationshipsTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe", gender: "male"})
    {:ok, spouse} = People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})
    {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "Doe", gender: "male"})

    %{family: family, person: person, spouse: spouse, child: child}
  end

  test "displays relationships section", %{conn: conn, family: family, person: person} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert html =~ "Spouses and Children"
    assert html =~ "Parents and Siblings"
  end

  test "displays existing partner relationship", %{
    conn: conn, family: family, person: person, spouse: spouse
  } do
    {:ok, _} = Relationships.create_relationship(person, spouse, "partner", %{marriage_year: 2020})
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert html =~ "Jane"
    assert html =~ "2020"
  end

  test "displays existing parent relationship", %{conn: conn, family: family, person: person} do
    {:ok, father} =
      People.create_person(family, %{given_name: "Dad", surname: "Doe", gender: "male"})

    {:ok, _} = Relationships.create_relationship(father, person, "parent", %{role: "father"})
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert html =~ "Dad"
    assert html =~ "father"
  end

  test "displays inferred children", %{
    conn: conn, family: family, person: person, spouse: spouse, child: child
  } do
    {:ok, _} = Relationships.create_relationship(person, spouse, "partner", %{marriage_year: 2020})
    {:ok, _} = Relationships.create_relationship(person, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(spouse, child, "parent", %{role: "mother"})

    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert html =~ "Kid"
    assert html =~ "Children (1)"
  end

  test "opens add parent modal", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("button", "+ Add Parent") |> render_click()
    assert has_element?(view, "#add-relationship-modal")
  end

  test "searches family members in add modal", %{conn: conn, family: family, person: person} do
    {:ok, _} = People.create_person(family, %{given_name: "Alice", surname: "Smith"})
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")

    view |> element("button", "+ Add Parent") |> render_click()
    view |> element("#relationship-search-input") |> render_keyup(%{"query" => "Alice"})

    assert render(view) =~ "Alice"
  end
end
```

**Step 2: Run the tests**

Run: `mix test test/web/live/person_live/relationships_test.exs`
Expected: all tests PASS

**Step 3: Commit**

```bash
git add test/web/live/person_live/relationships_test.exs
git commit -m "Add LiveView tests for person relationships"
```

---

## Task 13: Run precommit and fix issues

**Step 1: Run full precommit check**

Run: `mix precommit`
Expected: compile (warnings-as-errors), format, and tests all pass

**Step 2: Fix any issues found**

Address any compilation warnings, formatting issues, or test failures.

**Step 3: Commit fixes if any**

```bash
git add -A
git commit -m "Fix precommit issues"
```

---

## Notes for the implementer

- **`polymorphic_embed` integration**: The schema definition uses `polymorphic_embeds_one/2` and `cast_polymorphic_embed/3`. Check the [polymorphic_embed docs](https://hexdocs.pm/polymorphic_embed) if the API has changed. The type field in JSONB defaults to `__type__`.
- **`get_siblings/1` complexity**: This is the hardest function. The plan provides a starting implementation but expect to iterate on the Ecto queries. Test thoroughly.
- **Template `case` in HEEx**: Remember to use `<%= case ... do %>` with `<% pattern -> %>` syntax. Don't use `{case ...}` in tag bodies.
- **Existing test patterns**: Follow the fixture pattern in `test/ancestry/people_test.exs` — define `family_fixture/1` at the bottom of each test module.
- **Repo import**: `PersonLive.Show` doesn't currently alias `Repo` — you'll need to add it for `Repo.get!/2` in event handlers.
- **`search_family_members/3`**: This is a new function added to `Ancestry.People`, distinct from the existing `search_people/2` which excludes members of a given family. This new function searches *within* a family.
