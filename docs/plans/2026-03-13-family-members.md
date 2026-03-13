# Family Members Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add family members (persons) to the Ancestry app — a person has a structured name, alternate names, partial birth/death dates, gender, living status, and a profile photo, and can belong to multiple families.

**Architecture:** New `Ancestry.People` context with `Person` and `FamilyMember` schemas. Person photo processing follows the existing Oban/Waffle/PubSub pipeline. Three new LiveViews under `Web.PersonLive` handle listing, creation, and viewing/editing. Routes nested under `/families/:family_id/members`.

**Tech Stack:** Phoenix LiveView, Ecto, Oban, Waffle, PubSub, ImageMagick

---

### Task 1: Migration — persons table

**Files:**
- Create: `priv/repo/migrations/*_create_persons.exs` (via `mix ecto.gen.migration`)

**Step 1: Generate the migration**

Run: `mix ecto.gen.migration create_persons`

**Step 2: Write the migration**

```elixir
defmodule Ancestry.Repo.Migrations.CreatePersons do
  use Ecto.Migration

  def change do
    create table(:persons) do
      add :given_name, :text
      add :surname, :text
      add :given_name_at_birth, :text
      add :surname_at_birth, :text
      add :nickname, :text
      add :title, :text
      add :suffix, :text
      add :alternate_names, {:array, :text}, default: []
      add :birth_day, :integer
      add :birth_month, :integer
      add :birth_year, :integer
      add :death_day, :integer
      add :death_month, :integer
      add :death_year, :integer
      add :living, :text, default: "yes", null: false
      add :gender, :text
      add :photo, :text
      add :photo_status, :text

      timestamps()
    end
  end
end
```

**Step 3: Run the migration**

Run: `mix ecto.migrate`
Expected: migration succeeds

**Step 4: Commit**

```
git add priv/repo/migrations/*_create_persons.exs
git commit -m "Add persons migration"
```

---

### Task 2: Migration — family_members join table

**Files:**
- Create: `priv/repo/migrations/*_create_family_members.exs` (via `mix ecto.gen.migration`)

**Step 1: Generate the migration**

Run: `mix ecto.gen.migration create_family_members`

**Step 2: Write the migration**

```elixir
defmodule Ancestry.Repo.Migrations.CreateFamilyMembers do
  use Ecto.Migration

  def change do
    create table(:family_members) do
      add :family_id, references(:families, on_delete: :delete_all), null: false
      add :person_id, references(:persons, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:family_members, [:family_id])
    create index(:family_members, [:person_id])
    create unique_index(:family_members, [:family_id, :person_id])
  end
end
```

**Step 3: Run the migration**

Run: `mix ecto.migrate`
Expected: migration succeeds

**Step 4: Commit**

```
git add priv/repo/migrations/*_create_family_members.exs
git commit -m "Add family_members join table migration"
```

---

### Task 3: Person schema

**Files:**
- Create: `lib/ancestry/people/person.ex`
- Test: `test/ancestry/people_test.exs`

**Step 1: Write the failing test**

Create `test/ancestry/people_test.exs`:

```elixir
defmodule Ancestry.PeopleTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People
  alias Ancestry.People.Person

  describe "person changeset" do
    test "valid changeset with minimal fields" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe"})
      assert changeset.valid?
    end

    test "defaults living to yes" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe"})
      assert Ecto.Changeset.get_field(changeset, :living) == "yes"
    end

    test "validates living is one of yes, no, unknown" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe", living: "maybe"})
      assert "is invalid" in errors_on(changeset).living
    end

    test "validates gender is one of female, male, other" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe", gender: "invalid"})
      assert "is invalid" in errors_on(changeset).gender
    end

    test "validates birth_month in 1..12" do
      changeset = Person.changeset(%Person{}, %{given_name: "J", surname: "D", birth_month: 13})
      assert "must be less than or equal to 12" in errors_on(changeset).birth_month
    end

    test "validates birth_day in 1..31" do
      changeset = Person.changeset(%Person{}, %{given_name: "J", surname: "D", birth_day: 0})
      assert "must be greater than or equal to 1" in errors_on(changeset).birth_day
    end

    test "display_name/1 combines given_name and surname" do
      person = %Person{given_name: "John", surname: "Doe"}
      assert Person.display_name(person) == "John Doe"
    end

    test "display_name/1 handles nil given_name" do
      person = %Person{given_name: nil, surname: "Doe"}
      assert Person.display_name(person) == "Doe"
    end

    test "display_name/1 handles nil surname" do
      person = %Person{given_name: "John", surname: nil}
      assert Person.display_name(person) == "John"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/people_test.exs`
Expected: compilation error — `People` and `Person` modules don't exist

**Step 3: Write the Person schema**

Create `lib/ancestry/people/person.ex`:

```elixir
defmodule Ancestry.People.Person do
  use Ecto.Schema
  use Waffle.Ecto.Schema
  import Ecto.Changeset

  schema "persons" do
    field :given_name, :string
    field :surname, :string
    field :given_name_at_birth, :string
    field :surname_at_birth, :string
    field :nickname, :string
    field :title, :string
    field :suffix, :string
    field :alternate_names, {:array, :string}, default: []
    field :birth_day, :integer
    field :birth_month, :integer
    field :birth_year, :integer
    field :death_day, :integer
    field :death_month, :integer
    field :death_year, :integer
    field :living, :string, default: "yes"
    field :gender, :string
    field :photo, Ancestry.Uploaders.PersonPhoto.Type
    field :photo_status, :string

    many_to_many :families, Ancestry.Families.Family, join_through: "family_members"

    timestamps()
  end

  @cast_fields [
    :given_name, :surname, :given_name_at_birth, :surname_at_birth,
    :nickname, :title, :suffix, :alternate_names,
    :birth_day, :birth_month, :birth_year,
    :death_day, :death_month, :death_year,
    :living, :gender
  ]

  def changeset(person, attrs) do
    person
    |> cast(attrs, @cast_fields)
    |> validate_inclusion(:living, ~w(yes no unknown))
    |> validate_inclusion(:gender, ~w(female male other))
    |> validate_number(:birth_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:birth_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:birth_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
    |> validate_number(:death_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:death_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:death_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
  end

  def photo_changeset(person, attrs) do
    person
    |> cast_attachments(attrs, [:photo])
    |> cast(attrs, [:photo_status])
  end

  def display_name(%__MODULE__{given_name: given, surname: sur}) do
    [given, sur]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
```

**Step 4: Create a stub People context** (just enough for the test to compile)

Create `lib/ancestry/people.ex`:

```elixir
defmodule Ancestry.People do
end
```

**Step 5: Run test to verify it passes**

Run: `mix test test/ancestry/people_test.exs`
Expected: all tests pass

**Step 6: Commit**

```
git add lib/ancestry/people/person.ex lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "Add Person schema with changeset and display_name"
```

---

### Task 4: FamilyMember join schema

**Files:**
- Create: `lib/ancestry/people/family_member.ex`

**Step 1: Write the join schema**

Create `lib/ancestry/people/family_member.ex`:

```elixir
defmodule Ancestry.People.FamilyMember do
  use Ecto.Schema
  import Ecto.Changeset

  schema "family_members" do
    belongs_to :family, Ancestry.Families.Family
    belongs_to :person, Ancestry.People.Person

    timestamps()
  end

  def changeset(family_member, attrs) do
    family_member
    |> cast(attrs, [])
    |> foreign_key_constraint(:family_id)
    |> foreign_key_constraint(:person_id)
    |> unique_constraint([:family_id, :person_id])
  end
end
```

**Step 2: Update Family schema** to add `many_to_many :members`

In `lib/ancestry/families/family.ex`, add inside the schema block:

```elixir
many_to_many :members, Ancestry.People.Person, join_through: "family_members"
```

**Step 3: Commit**

```
git add lib/ancestry/people/family_member.ex lib/ancestry/families/family.ex
git commit -m "Add FamilyMember join schema and Family.members association"
```

---

### Task 5: People context — core CRUD

**Files:**
- Modify: `lib/ancestry/people.ex`
- Modify: `test/ancestry/people_test.exs`

**Step 1: Write the failing tests**

Add to `test/ancestry/people_test.exs`:

```elixir
  describe "create_person/2" do
    test "creates a person and adds to family" do
      family = family_fixture()
      assert {:ok, %Person{} = person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      assert person.given_name == "Jane"
      assert person.surname == "Doe"

      people = People.list_people_for_family(family.id)
      assert length(people) == 1
      assert hd(people).id == person.id
    end

    test "returns error changeset with invalid living value" do
      family = family_fixture()
      assert {:error, %Ecto.Changeset{}} = People.create_person(family, %{given_name: "J", surname: "D", living: "maybe"})
    end
  end

  describe "list_people_for_family/1" do
    test "returns only people in the given family" do
      family1 = family_fixture(%{name: "Family One"})
      family2 = family_fixture(%{name: "Family Two"})
      {:ok, person1} = People.create_person(family1, %{given_name: "Alice", surname: "A"})
      {:ok, _person2} = People.create_person(family2, %{given_name: "Bob", surname: "B"})

      people = People.list_people_for_family(family1.id)
      assert length(people) == 1
      assert hd(people).id == person1.id
    end
  end

  describe "get_person!/1" do
    test "returns the person" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      fetched = People.get_person!(person.id)
      assert fetched.id == person.id
    end
  end

  describe "update_person/2" do
    test "updates person fields" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      assert {:ok, updated} = People.update_person(person, %{given_name: "Janet"})
      assert updated.given_name == "Janet"
    end
  end

  describe "delete_person/1" do
    test "deletes the person" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      assert {:ok, _} = People.delete_person(person)
      assert_raise Ecto.NoResultsError, fn -> People.get_person!(person.id) end
    end
  end

  describe "add_to_family/2 and remove_from_family/2" do
    test "adds an existing person to another family" do
      family1 = family_fixture(%{name: "Family One"})
      family2 = family_fixture(%{name: "Family Two"})
      {:ok, person} = People.create_person(family1, %{given_name: "Jane", surname: "Doe"})

      assert {:ok, _} = People.add_to_family(person, family2)
      assert length(People.list_people_for_family(family2.id)) == 1
    end

    test "add_to_family returns error for duplicate membership" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      assert {:error, _} = People.add_to_family(person, family)
    end

    test "removes a person from a family" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      assert {:ok, _} = People.remove_from_family(person, family)
      assert People.list_people_for_family(family.id) == []
    end
  end

  describe "search_people/2" do
    test "searches by given_name, surname, nickname" do
      family = family_fixture()
      {:ok, _} = People.create_person(family, %{given_name: "Alice", surname: "Wonderland", nickname: "Ali"})
      {:ok, _} = People.create_person(family, %{given_name: "Bob", surname: "Builder"})

      assert length(People.search_people("alice", family.id)) == 1
      assert length(People.search_people("ali", family.id)) == 1
      assert length(People.search_people("wonder", family.id)) == 1
      assert length(People.search_people("bob", family.id)) == 0
    end
  end

  describe "change_person/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = People.change_person(%Person{})
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

Run: `mix test test/ancestry/people_test.exs`
Expected: failures — functions don't exist

**Step 3: Implement the People context**

Replace `lib/ancestry/people.ex`:

```elixir
defmodule Ancestry.People do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.Person
  alias Ancestry.People.FamilyMember

  def list_people_for_family(family_id) do
    Repo.all(
      from p in Person,
        join: fm in FamilyMember, on: fm.person_id == p.id,
        where: fm.family_id == ^family_id,
        order_by: [asc: p.surname, asc: p.given_name]
    )
  end

  def get_person!(id), do: Repo.get!(Person, id)

  def create_person(family, attrs) do
    Repo.transaction(fn ->
      case %Person{} |> Person.changeset(attrs) |> Repo.insert() do
        {:ok, person} ->
          %FamilyMember{family_id: family.id, person_id: person.id}
          |> FamilyMember.changeset(%{})
          |> Repo.insert!()

          person

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def update_person(%Person{} = person, attrs) do
    person
    |> Person.changeset(attrs)
    |> Repo.update()
  end

  def delete_person(%Person{} = person) do
    cleanup_person_files(person)
    Repo.delete(person)
  end

  def add_to_family(%Person{} = person, family) do
    %FamilyMember{family_id: family.id, person_id: person.id}
    |> FamilyMember.changeset(%{})
    |> Repo.insert()
  end

  def remove_from_family(%Person{} = person, family) do
    Repo.delete_all(
      from fm in FamilyMember,
        where: fm.family_id == ^family.id and fm.person_id == ^person.id
    )
    |> case do
      {1, _} -> {:ok, person}
      {0, _} -> {:error, :not_found}
    end
  end

  def search_people(query, exclude_family_id) do
    like = "%#{query}%"

    Repo.all(
      from p in Person,
        left_join: fm in FamilyMember, on: fm.person_id == p.id and fm.family_id == ^exclude_family_id,
        where: is_nil(fm.id),
        where:
          ilike(p.given_name, ^like) or
          ilike(p.surname, ^like) or
          ilike(p.nickname, ^like),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20
    )
  end

  def change_person(%Person{} = person, attrs \\ %{}) do
    Person.changeset(person, attrs)
  end

  defp cleanup_person_files(person) do
    photo_dir = Path.join(["priv", "static", "uploads", "people", "#{person.id}"])
    File.rm_rf(photo_dir)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/people_test.exs`
Expected: all pass

**Step 5: Commit**

```
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "Add People context with CRUD, family membership, and search"
```

---

### Task 6: PersonPhoto uploader and Oban worker

**Files:**
- Create: `lib/ancestry/uploaders/person_photo.ex`
- Create: `lib/ancestry/workers/process_person_photo_job.ex`
- Test: `test/ancestry/workers/process_person_photo_job_test.exs`

**Step 1: Create the Waffle uploader**

Create `lib/ancestry/uploaders/person_photo.ex`:

```elixir
defmodule Ancestry.Uploaders.PersonPhoto do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original, :thumbnail]
  @valid_extensions ~w(.jpg .jpeg .png .webp .tif .tiff)

  def validate({file, _}) do
    file.file_name
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @valid_extensions))
  end

  def transform(:original, _), do: :noaction

  def transform(:thumbnail, _) do
    {:convert, "-resize 400x400> -auto-orient -strip", :jpg}
  end

  def filename(:original, {file, _}) do
    "original#{Path.extname(file.file_name) |> String.downcase()}"
  end

  def filename(:thumbnail, _), do: "thumbnail.jpg"

  def storage_dir(_version, {_file, scope}) do
    "uploads/people/#{scope.id}"
  end
end
```

**Step 2: Create the Oban worker**

Create `lib/ancestry/workers/process_person_photo_job.ex`:

```elixir
defmodule Ancestry.Workers.ProcessPersonPhotoJob do
  use Oban.Worker, queue: :photos, max_attempts: 3

  alias Ancestry.People
  alias Ancestry.Uploaders

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"person_id" => person_id, "original_path" => original_path}}) do
    person = People.get_person!(person_id)

    case process_photo(person, original_path) do
      {:ok, updated_person} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "person:#{person.id}",
          {:person_photo_processed, updated_person}
        )

        :ok

      {:error, reason} ->
        {:ok, _} = People.update_photo_failed(person)

        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "person:#{person.id}",
          {:person_photo_failed, person}
        )

        {:error, reason}
    end
  end

  defp process_photo(person, original_path) do
    waffle_file = %{
      filename: Path.basename(original_path),
      path: original_path
    }

    case Uploaders.PersonPhoto.store({waffle_file, person}) do
      {:ok, filename} -> People.update_photo_processed(person, filename)
      {:error, reason} -> {:error, reason}
    end
  end
end
```

**Step 3: Add photo helper functions to People context**

Add to `lib/ancestry/people.ex`:

```elixir
  def update_photo_pending(%Person{} = person, original_path) do
    person
    |> Ecto.Changeset.change(%{photo_status: "pending"})
    |> Repo.update!()

    Oban.insert(
      Ancestry.Workers.ProcessPersonPhotoJob.new(%{
        person_id: person.id,
        original_path: original_path
      })
    )
  end

  def update_photo_processed(%Person{} = person, filename) do
    person
    |> Ecto.Changeset.change(%{
      photo: %{file_name: filename, updated_at: nil},
      photo_status: "processed"
    })
    |> Repo.update()
  end

  def update_photo_failed(%Person{} = person) do
    person
    |> Ecto.Changeset.change(%{photo_status: "failed"})
    |> Repo.update()
  end
```

**Step 4: Write the worker test**

Create `test/ancestry/workers/process_person_photo_job_test.exs`:

```elixir
defmodule Ancestry.Workers.ProcessPersonPhotoJobTest do
  use Ancestry.DataCase, async: false
  use Oban.Testing, repo: Ancestry.Repo

  alias Ancestry.People
  alias Ancestry.Workers.ProcessPersonPhotoJob

  setup do
    {:ok, family} = Ancestry.Families.create_family(%{name: "Test Family"})
    {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})

    src = Path.absname("test/fixtures/test_image.jpg")
    uuid = Ecto.UUID.generate()
    dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
    File.mkdir_p!(dest_dir)
    dest_path = Path.join(dest_dir, "photo.jpg")
    File.cp!(src, dest_path)

    on_exit(fn ->
      File.rm_rf!(dest_dir)
      File.rm_rf!(Path.join(["priv", "static", "uploads", "people", "#{person.id}"]))
    end)

    %{person: person, original_path: dest_path}
  end

  test "processes photo and broadcasts success", %{person: person, original_path: original_path} do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "person:#{person.id}")

    assert :ok = perform_job(ProcessPersonPhotoJob, %{person_id: person.id, original_path: original_path})

    updated = People.get_person!(person.id)
    assert updated.photo_status == "processed"
    assert updated.photo

    assert_receive {:person_photo_processed, _}
  end
end
```

**Step 5: Run test**

Run: `mix test test/ancestry/workers/process_person_photo_job_test.exs`
Expected: passes

**Step 6: Commit**

```
git add lib/ancestry/uploaders/person_photo.ex lib/ancestry/workers/process_person_photo_job.ex lib/ancestry/people.ex test/ancestry/workers/process_person_photo_job_test.exs
git commit -m "Add PersonPhoto uploader and ProcessPersonPhotoJob worker"
```

---

### Task 7: Routes

**Files:**
- Modify: `lib/web/router.ex`

**Step 1: Add routes**

In `lib/web/router.ex`, inside the existing `live_session :default` block, add:

```elixir
live "/families/:family_id/members", PersonLive.Index, :index
live "/families/:family_id/members/new", PersonLive.New, :new
live "/families/:family_id/members/:id", PersonLive.Show, :show
```

**Step 2: Commit**

```
git add lib/web/router.ex
git commit -m "Add person routes nested under families"
```

---

### Task 8: PersonLive.New — create new person

**Files:**
- Create: `lib/web/live/person_live/new.ex`
- Create: `lib/web/live/person_live/new.html.heex`
- Test: `test/web/live/person_live/new_test.exs`

**Step 1: Write the failing test**

Create `test/web/live/person_live/new_test.exs`:

```elixir
defmodule Web.PersonLive.NewTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    %{family: family}
  end

  test "renders new person form", %{conn: conn, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/new")
    assert html =~ "New Member"
  end

  test "creates a person and redirects to members index", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

    result =
      view
      |> form("#new-person-form", person: %{given_name: "Jane", surname: "Doe", gender: "female"})
      |> render_submit()

    assert_redirect(view, ~p"/families/#{family.id}/members")
  end

  test "validates form on change", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/new")

    view
    |> form("#new-person-form", person: %{living: "maybe"})
    |> render_change()

    assert has_element?(view, "#new-person-form")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/web/live/person_live/new_test.exs`
Expected: compilation error — module doesn't exist

**Step 3: Write the LiveView**

Create `lib/web/live/person_live/new.ex`:

```elixir
defmodule Web.PersonLive.New do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:form, to_form(People.change_person(%Person{})))
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", %{"person" => params}, socket) do
    changeset =
      %Person{}
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    family = socket.assigns.family

    case People.create_person(family, params) do
      {:ok, person} ->
        socket = maybe_process_photo(socket, person)
        {:noreply, push_navigate(socket, to: ~p"/families/#{family.id}/members")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  defp maybe_process_photo(socket, person) do
    uploaded =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = Path.extname(entry.client_name)
        dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "photo#{ext}")
        File.cp!(tmp_path, dest_path)
        {:ok, dest_path}
      end)

    case uploaded do
      [original_path] ->
        People.update_photo_pending(person, original_path)
        socket

      [] ->
        socket
    end
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 20MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not supported"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
```

**Step 4: Write the template**

Create `lib/web/live/person_live/new.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <:toolbar>
    <div class="max-w-7xl mx-auto flex items-center justify-between py-3">
      <div class="flex items-center gap-3">
        <.link
          navigate={~p"/families/#{@family.id}/members"}
          class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-5 h-5" />
        </.link>
        <h1 class="text-2xl font-bold text-base-content">New Member</h1>
      </div>
    </div>
  </:toolbar>

  <div class="max-w-2xl mx-auto mt-8">
    <.form
      for={@form}
      id="new-person-form"
      phx-submit="save"
      phx-change="validate"
      multipart
    >
      <div class="space-y-8">
        <%!-- Name section --%>
        <div>
          <h2 class="text-lg font-semibold text-base-content mb-4">Name</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input field={@form[:title]} label="Title" placeholder="e.g. Dr., Sir" />
            <.input field={@form[:given_name]} label="Given name" />
            <.input field={@form[:nickname]} label="Nickname" />
            <.input field={@form[:surname]} label="Surname" />
            <.input field={@form[:suffix]} label="Suffix" placeholder="e.g. Jr., III" />
            <.input field={@form[:given_name_at_birth]} label="Given name at birth" />
            <.input field={@form[:surname_at_birth]} label="Surname at birth" />
          </div>
        </div>

        <%!-- Alternate names --%>
        <div>
          <h2 class="text-lg font-semibold text-base-content mb-4">Alternate Names</h2>
          <p class="text-sm text-base-content/50 mb-3">Also known as (one per line)</p>
          <textarea
            name="person[alternate_names_text]"
            id="person-alternate-names"
            rows="3"
            class="textarea textarea-bordered w-full"
            phx-debounce="300"
          ></textarea>
        </div>

        <%!-- Dates section --%>
        <div>
          <h2 class="text-lg font-semibold text-base-content mb-4">Dates</h2>
          <div class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-base-content mb-2">Date of birth</label>
              <div class="grid grid-cols-3 gap-3">
                <.input field={@form[:birth_day]} type="number" placeholder="Day" />
                <.input field={@form[:birth_month]} type="number" placeholder="Month" />
                <.input field={@form[:birth_year]} type="number" placeholder="Year" />
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-base-content mb-2">Date of death</label>
              <div class="grid grid-cols-3 gap-3">
                <.input field={@form[:death_day]} type="number" placeholder="Day" />
                <.input field={@form[:death_month]} type="number" placeholder="Month" />
                <.input field={@form[:death_year]} type="number" placeholder="Year" />
              </div>
            </div>
          </div>
        </div>

        <%!-- Status section --%>
        <div>
          <h2 class="text-lg font-semibold text-base-content mb-4">Details</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:living]}
              type="select"
              label="Living"
              options={[{"Yes", "yes"}, {"No", "no"}, {"Unknown", "unknown"}]}
            />
            <.input
              field={@form[:gender]}
              type="select"
              label="Gender"
              prompt="Select..."
              options={[{"Female", "female"}, {"Male", "male"}, {"Other", "other"}]}
            />
          </div>
        </div>

        <%!-- Photo section --%>
        <div>
          <h2 class="text-lg font-semibold text-base-content mb-4">Photo</h2>
          <.live_file_input upload={@uploads.photo} class="file-input file-input-bordered w-full" />

          <%= for entry <- @uploads.photo.entries do %>
            <div class="mt-3 flex items-center gap-3">
              <.live_img_preview entry={entry} class="w-20 h-20 rounded-lg object-cover" />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-base-content truncate">{entry.client_name}</p>
                <div class="mt-1 h-1.5 bg-base-200 rounded-full overflow-hidden">
                  <div
                    class="h-full bg-primary rounded-full transition-all duration-300"
                    style={"width: #{entry.progress}%"}
                  >
                  </div>
                </div>
              </div>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="p-1.5 rounded-lg text-base-content/30 hover:text-error hover:bg-error/10 transition-all"
              >
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </div>
          <% end %>

          <%= for err <- upload_errors(@uploads.photo) do %>
            <p class="text-error text-sm mt-2">{upload_error_to_string(err)}</p>
          <% end %>
        </div>
      </div>

      <div class="flex gap-3 mt-8">
        <button type="submit" class="btn btn-primary flex-1">Create</button>
        <.link navigate={~p"/families/#{@family.id}/members"} class="btn btn-ghost flex-1">Cancel</.link>
      </div>
    </.form>
  </div>
</Layouts.app>
```

**Step 5: Handle alternate_names_text in the changeset**

The textarea sends `alternate_names_text` as a single string. Handle this in the LiveView's `handle_event("save", ...)` by splitting:

In `new.ex`, update the `save` handler to preprocess params:

```elixir
  def handle_event("save", %{"person" => params}, socket) do
    params = process_alternate_names(params)
    family = socket.assigns.family

    case People.create_person(family, params) do
      # ... rest unchanged
    end
  end

  defp process_alternate_names(params) do
    case Map.pop(params, "alternate_names_text") do
      {nil, params} -> params
      {"", params} -> params
      {text, params} ->
        names = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(params, "alternate_names", names)
    end
  end
```

**Step 6: Run tests**

Run: `mix test test/web/live/person_live/new_test.exs`
Expected: passes

**Step 7: Commit**

```
git add lib/web/live/person_live/new.ex lib/web/live/person_live/new.html.heex test/web/live/person_live/new_test.exs
git commit -m "Add PersonLive.New for creating family members"
```

---

### Task 9: PersonLive.Index — list family members

**Files:**
- Create: `lib/web/live/person_live/index.ex`
- Create: `lib/web/live/person_live/index.html.heex`
- Test: `test/web/live/person_live/index_test.exs`

**Step 1: Write the failing test**

Create `test/web/live/person_live/index_test.exs`:

```elixir
defmodule Web.PersonLive.IndexTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    %{family: family}
  end

  test "lists family members", %{conn: conn, family: family} do
    {:ok, _person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members")
    assert html =~ "Jane Doe"
  end

  test "shows empty state when no members", %{conn: conn, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members")
    assert html =~ "No members yet"
  end

  test "has add member button", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members")
    assert has_element?(view, "#add-member-btn")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/web/live/person_live/index_test.exs`
Expected: compilation error

**Step 3: Write the LiveView**

Create `lib/web/live/person_live/index.ex`:

```elixir
defmodule Web.PersonLive.Index do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:search_mode, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> stream(:members, People.list_people_for_family(family_id))}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_search", _, socket) do
    {:noreply, assign(socket, :search_mode, true)}
  end

  def handle_event("close_search", _, socket) do
    {:noreply, socket |> assign(:search_mode, false) |> assign(:search_results, []) |> assign(:search_query, "")}
  end

  def handle_event("search", %{"query" => query}, socket) do
    results =
      if String.length(String.trim(query)) >= 2 do
        People.search_people(query, socket.assigns.family.id)
      else
        []
      end

    {:noreply, socket |> assign(:search_query, query) |> assign(:search_results, results)}
  end

  def handle_event("link_person", %{"id" => id}, socket) do
    person = People.get_person!(String.to_integer(id))
    family = socket.assigns.family

    case People.add_to_family(person, family) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_insert(:members, person)
         |> assign(:search_mode, false)
         |> assign(:search_results, [])
         |> assign(:search_query, "")}

      {:error, _} ->
        {:noreply, socket}
    end
  end
end
```

**Step 4: Write the template**

Create `lib/web/live/person_live/index.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <:toolbar>
    <div class="max-w-7xl mx-auto flex items-center justify-between py-3">
      <div class="flex items-center gap-3">
        <.link
          navigate={~p"/families/#{@family.id}"}
          class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-5 h-5" />
        </.link>
        <h1 class="text-2xl font-bold text-base-content">{@family.name} — Members</h1>
      </div>
      <div class="flex items-center gap-2">
        <button
          id="link-existing-btn"
          phx-click="open_search"
          class="btn btn-ghost btn-sm"
        >
          <.icon name="hero-magnifying-glass" class="w-4 h-4" /> Link Existing
        </button>
        <.link
          id="add-member-btn"
          navigate={~p"/families/#{@family.id}/members/new"}
          class="btn btn-primary btn-sm"
        >
          <.icon name="hero-plus" class="w-4 h-4" /> Add Member
        </.link>
      </div>
    </div>
  </:toolbar>

  <div class="max-w-7xl mx-auto">
    <div
      id="members"
      phx-update="stream"
      class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-5"
    >
      <div
        id="members-empty"
        class="hidden only:block col-span-full text-center py-20 text-base-content/40"
      >
        No members yet. Add your first family member.
      </div>
      <.link
        :for={{id, person} <- @streams.members}
        id={id}
        navigate={~p"/families/#{@family.id}/members/#{person.id}"}
        class="card bg-base-100 shadow-sm border border-base-200 hover:shadow-md transition-all duration-200 p-6"
      >
        <div class="flex items-center gap-4">
          <div class="w-14 h-14 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 overflow-hidden">
            <%= if person.photo && person.photo_status == "processed" do %>
              <img
                src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                alt={Ancestry.People.Person.display_name(person)}
                class="w-full h-full object-cover"
              />
            <% else %>
              <.icon name="hero-user" class="w-7 h-7 text-primary" />
            <% end %>
          </div>
          <div class="min-w-0">
            <h2 class="text-lg font-semibold text-base-content truncate">
              {Ancestry.People.Person.display_name(person)}
            </h2>
            <%= if person.birth_year do %>
              <p class="text-sm text-base-content/50">b. {person.birth_year}</p>
            <% end %>
          </div>
        </div>
      </.link>
    </div>
  </div>

  <%!-- Search/Link Existing Modal --%>
  <%= if @search_mode do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="close_search"></div>
      <div
        id="link-person-modal"
        class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8"
      >
        <h2 class="text-xl font-bold text-base-content mb-4">Link Existing Person</h2>
        <input
          id="person-search-input"
          type="text"
          name="query"
          value={@search_query}
          placeholder="Search by name..."
          phx-keyup="search"
          phx-debounce="300"
          autofocus
          class="input input-bordered w-full mb-4"
        />
        <div class="max-h-64 overflow-y-auto space-y-2">
          <%= if @search_results == [] && String.length(String.trim(@search_query)) >= 2 do %>
            <p class="text-base-content/40 text-sm text-center py-4">No results found</p>
          <% end %>
          <%= for person <- @search_results do %>
            <button
              id={"link-person-#{person.id}"}
              phx-click="link_person"
              phx-value-id={person.id}
              class="w-full flex items-center gap-3 p-3 rounded-lg hover:bg-base-200 transition-colors text-left"
            >
              <div class="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                <.icon name="hero-user" class="w-5 h-5 text-primary" />
              </div>
              <div class="min-w-0">
                <p class="font-medium text-base-content truncate">
                  {Ancestry.People.Person.display_name(person)}
                </p>
              </div>
            </button>
          <% end %>
        </div>
        <button phx-click="close_search" class="btn btn-ghost w-full mt-4">Cancel</button>
      </div>
    </div>
  <% end %>
</Layouts.app>
```

**Step 5: Run tests**

Run: `mix test test/web/live/person_live/index_test.exs`
Expected: passes

**Step 6: Commit**

```
git add lib/web/live/person_live/index.ex lib/web/live/person_live/index.html.heex test/web/live/person_live/index_test.exs
git commit -m "Add PersonLive.Index with member listing and link-existing search"
```

---

### Task 10: PersonLive.Show — view and edit person

**Files:**
- Create: `lib/web/live/person_live/show.ex`
- Create: `lib/web/live/person_live/show.html.heex`
- Test: `test/web/live/person_live/show_test.exs`

**Step 1: Write the failing test**

Create `test/web/live/person_live/show_test.exs`:

```elixir
defmodule Web.PersonLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female", living: "yes"})
    %{family: family, person: person}
  end

  test "shows person details", %{conn: conn, family: family, person: person} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    assert html =~ "Jane"
    assert html =~ "Doe"
  end

  test "edits person name", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#edit-person-btn") |> render_click()

    view
    |> form("#edit-person-form", person: %{given_name: "Janet"})
    |> render_submit()

    assert render(view) =~ "Janet"
  end

  test "removes person from family", %{conn: conn, family: family, person: person} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#remove-from-family-btn") |> render_click()
    view |> element("#confirm-remove-btn") |> render_click()
    assert_redirect(view, ~p"/families/#{family.id}/members")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/web/live/person_live/show_test.exs`
Expected: compilation error

**Step 3: Write the LiveView**

Create `lib/web/live/person_live/show.ex`:

```elixir
defmodule Web.PersonLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(%{"family_id" => family_id, "id" => id}, _session, socket) do
    family = Families.get_family!(family_id)
    person = People.get_person!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "person:#{person.id}")
    end

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:person, person)
     |> assign(:editing, false)
     |> assign(:confirm_remove, false)
     |> assign(:form, to_form(People.change_person(person)))
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("edit", _, socket) do
    form = to_form(People.change_person(socket.assigns.person))
    {:noreply, socket |> assign(:editing, true) |> assign(:form, form)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("validate", %{"person" => params}, socket) do
    changeset =
      socket.assigns.person
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    params = process_alternate_names(params)

    case People.update_person(socket.assigns.person, params) do
      {:ok, person} ->
        socket = maybe_process_photo(socket, person)

        {:noreply,
         socket
         |> assign(:person, person)
         |> assign(:editing, false)
         |> assign(:form, to_form(People.change_person(person)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("request_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, true)}
  end

  def handle_event("cancel_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, false)}
  end

  def handle_event("confirm_remove", _, socket) do
    family = socket.assigns.family
    person = socket.assigns.person
    {:ok, _} = People.remove_from_family(person, family)
    {:noreply, push_navigate(socket, to: ~p"/families/#{family.id}/members")}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  @impl true
  def handle_info({:person_photo_processed, person}, socket) do
    {:noreply, assign(socket, :person, person)}
  end

  def handle_info({:person_photo_failed, person}, socket) do
    {:noreply, assign(socket, :person, person)}
  end

  defp process_alternate_names(params) do
    case Map.pop(params, "alternate_names_text") do
      {nil, params} -> params
      {"", params} -> params
      {text, params} ->
        names = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(params, "alternate_names", names)
    end
  end

  defp maybe_process_photo(socket, person) do
    uploaded =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = Path.extname(entry.client_name)
        dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "photo#{ext}")
        File.cp!(tmp_path, dest_path)
        {:ok, dest_path}
      end)

    case uploaded do
      [original_path] ->
        People.update_photo_pending(person, original_path)
        socket

      [] ->
        socket
    end
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 20MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not supported"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
```

**Step 4: Write the template**

Create `lib/web/live/person_live/show.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <:toolbar>
    <div class="max-w-7xl mx-auto flex items-center justify-between py-3">
      <div class="flex items-center gap-3">
        <.link
          navigate={~p"/families/#{@family.id}/members"}
          class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-5 h-5" />
        </.link>
        <h1 class="text-2xl font-bold text-base-content">
          {Ancestry.People.Person.display_name(@person)}
        </h1>
      </div>
      <div class="flex items-center gap-2">
        <button id="edit-person-btn" phx-click="edit" class="btn btn-ghost btn-sm">
          <.icon name="hero-pencil" class="w-4 h-4" /> Edit
        </button>
        <button id="remove-from-family-btn" phx-click="request_remove" class="btn btn-ghost btn-sm text-error">
          <.icon name="hero-user-minus" class="w-4 h-4" /> Remove
        </button>
      </div>
    </div>
  </:toolbar>

  <div class="max-w-4xl mx-auto">
    <div class="flex flex-col md:flex-row gap-8">
      <%!-- Photo --%>
      <div class="flex-shrink-0">
        <div class="w-48 h-48 rounded-2xl bg-base-200 flex items-center justify-center overflow-hidden">
          <%= if @person.photo && @person.photo_status == "processed" do %>
            <img
              src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :original)}
              alt={Ancestry.People.Person.display_name(@person)}
              class="w-full h-full object-cover"
            />
          <% else %>
            <.icon name="hero-user" class="w-16 h-16 text-base-content/20" />
          <% end %>
        </div>
      </div>

      <%!-- Details --%>
      <div class="flex-1 space-y-6">
        <div>
          <h2 class="text-sm font-medium text-base-content/50 uppercase tracking-wide mb-2">Name</h2>
          <div class="grid grid-cols-2 gap-x-8 gap-y-2 text-base-content">
            <%= if @person.title do %>
              <div><span class="text-base-content/50 text-sm">Title:</span> {@person.title}</div>
            <% end %>
            <%= if @person.given_name do %>
              <div><span class="text-base-content/50 text-sm">Given name:</span> {@person.given_name}</div>
            <% end %>
            <%= if @person.surname do %>
              <div><span class="text-base-content/50 text-sm">Surname:</span> {@person.surname}</div>
            <% end %>
            <%= if @person.nickname do %>
              <div><span class="text-base-content/50 text-sm">Nickname:</span> {@person.nickname}</div>
            <% end %>
            <%= if @person.suffix do %>
              <div><span class="text-base-content/50 text-sm">Suffix:</span> {@person.suffix}</div>
            <% end %>
            <%= if @person.given_name_at_birth do %>
              <div><span class="text-base-content/50 text-sm">Given name at birth:</span> {@person.given_name_at_birth}</div>
            <% end %>
            <%= if @person.surname_at_birth do %>
              <div><span class="text-base-content/50 text-sm">Surname at birth:</span> {@person.surname_at_birth}</div>
            <% end %>
          </div>
        </div>

        <%= if @person.alternate_names != [] do %>
          <div>
            <h2 class="text-sm font-medium text-base-content/50 uppercase tracking-wide mb-2">Also Known As</h2>
            <div class="flex flex-wrap gap-2">
              <%= for name <- @person.alternate_names do %>
                <span class="badge badge-outline">{name}</span>
              <% end %>
            </div>
          </div>
        <% end %>

        <div>
          <h2 class="text-sm font-medium text-base-content/50 uppercase tracking-wide mb-2">Details</h2>
          <div class="grid grid-cols-2 gap-x-8 gap-y-2 text-base-content">
            <%= if @person.birth_year || @person.birth_month || @person.birth_day do %>
              <div>
                <span class="text-base-content/50 text-sm">Born:</span>
                {format_partial_date(@person.birth_day, @person.birth_month, @person.birth_year)}
              </div>
            <% end %>
            <%= if @person.death_year || @person.death_month || @person.death_day do %>
              <div>
                <span class="text-base-content/50 text-sm">Died:</span>
                {format_partial_date(@person.death_day, @person.death_month, @person.death_year)}
              </div>
            <% end %>
            <div><span class="text-base-content/50 text-sm">Living:</span> {String.capitalize(@person.living)}</div>
            <%= if @person.gender do %>
              <div><span class="text-base-content/50 text-sm">Gender:</span> {String.capitalize(@person.gender)}</div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
  </div>

  <%!-- Edit Modal --%>
  <%= if @editing do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_edit"></div>
      <div class="relative card bg-base-100 shadow-2xl w-full max-w-2xl mx-4 my-8 p-8">
        <h2 class="text-xl font-bold text-base-content mb-6">Edit Member</h2>
        <.form
          for={@form}
          id="edit-person-form"
          phx-submit="save"
          phx-change="validate"
          multipart
        >
          <div class="space-y-6">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.input field={@form[:title]} label="Title" />
              <.input field={@form[:given_name]} label="Given name" />
              <.input field={@form[:nickname]} label="Nickname" />
              <.input field={@form[:surname]} label="Surname" />
              <.input field={@form[:suffix]} label="Suffix" />
              <.input field={@form[:given_name_at_birth]} label="Given name at birth" />
              <.input field={@form[:surname_at_birth]} label="Surname at birth" />
            </div>

            <div>
              <label class="block text-sm font-medium text-base-content mb-2">Alternate names (one per line)</label>
              <textarea
                name="person[alternate_names_text]"
                id="edit-person-alternate-names"
                rows="3"
                class="textarea textarea-bordered w-full"
                phx-debounce="300"
              >{Enum.join(@person.alternate_names, "\n")}</textarea>
            </div>

            <div class="grid grid-cols-3 gap-3">
              <.input field={@form[:birth_day]} type="number" label="Birth day" />
              <.input field={@form[:birth_month]} type="number" label="Birth month" />
              <.input field={@form[:birth_year]} type="number" label="Birth year" />
            </div>

            <div class="grid grid-cols-3 gap-3">
              <.input field={@form[:death_day]} type="number" label="Death day" />
              <.input field={@form[:death_month]} type="number" label="Death month" />
              <.input field={@form[:death_year]} type="number" label="Death year" />
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.input
                field={@form[:living]}
                type="select"
                label="Living"
                options={[{"Yes", "yes"}, {"No", "no"}, {"Unknown", "unknown"}]}
              />
              <.input
                field={@form[:gender]}
                type="select"
                label="Gender"
                prompt="Select..."
                options={[{"Female", "female"}, {"Male", "male"}, {"Other", "other"}]}
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-base-content mb-2">Photo</label>
              <.live_file_input upload={@uploads.photo} class="file-input file-input-bordered w-full" />

              <%= for entry <- @uploads.photo.entries do %>
                <div class="mt-3 flex items-center gap-3">
                  <.live_img_preview entry={entry} class="w-16 h-16 rounded-lg object-cover" />
                  <p class="text-sm truncate flex-1">{entry.client_name}</p>
                  <button
                    type="button"
                    phx-click="cancel_upload"
                    phx-value-ref={entry.ref}
                    class="p-1.5 rounded-lg text-base-content/30 hover:text-error hover:bg-error/10 transition-all"
                  >
                    <.icon name="hero-x-mark" class="w-4 h-4" />
                  </button>
                </div>
              <% end %>

              <%= for err <- upload_errors(@uploads.photo) do %>
                <p class="text-error text-sm mt-2">{upload_error_to_string(err)}</p>
              <% end %>
            </div>
          </div>

          <div class="flex gap-3 mt-6">
            <button type="submit" class="btn btn-primary flex-1">Save</button>
            <button type="button" phx-click="cancel_edit" class="btn btn-ghost flex-1">Cancel</button>
          </div>
        </.form>
      </div>
    </div>
  <% end %>

  <%!-- Remove Confirmation Modal --%>
  <%= if @confirm_remove do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_remove"></div>
      <div class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8">
        <h2 class="text-xl font-bold text-base-content mb-2">Remove from Family</h2>
        <p class="text-base-content/60 mb-6">
          Remove <span class="font-semibold">{Ancestry.People.Person.display_name(@person)}</span> from <span class="font-semibold">{@family.name}</span>? The person will still exist and can be linked to other families.
        </p>
        <div class="flex gap-3">
          <button id="confirm-remove-btn" phx-click="confirm_remove" class="btn btn-error flex-1">Remove</button>
          <button phx-click="cancel_remove" class="btn btn-ghost flex-1">Cancel</button>
        </div>
      </div>
    </div>
  <% end %>
</Layouts.app>
```

**Step 5: Add the `format_partial_date` helper to the LiveView module**

Add to `lib/web/live/person_live/show.ex`:

```elixir
  defp format_partial_date(day, month, year) do
    [day, month, year]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> ""
      parts -> Enum.join(parts, "/")
    end
  end
```

**Step 6: Run tests**

Run: `mix test test/web/live/person_live/show_test.exs`
Expected: passes

**Step 7: Commit**

```
git add lib/web/live/person_live/show.ex lib/web/live/person_live/show.html.heex test/web/live/person_live/show_test.exs
git commit -m "Add PersonLive.Show with view, edit, and remove-from-family"
```

---

### Task 11: Add Members link to Family Show page

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`

**Step 1: Add the members link**

In `lib/web/live/family_live/show.html.heex`, after the "View Galleries" link, add:

```heex
    <.link
      navigate={~p"/families/#{@family.id}/members"}
      class="btn btn-primary"
    >
      <.icon name="hero-users" class="w-5 h-5" /> View Members
    </.link>
```

**Step 2: Commit**

```
git add lib/web/live/family_live/show.html.heex
git commit -m "Add members link to family show page"
```

---

### Task 12: Run precommit and fix issues

**Step 1: Run precommit**

Run: `mix precommit`
Expected: compiles cleanly, formatted, tests pass

**Step 2: Fix any issues found**

Address any compiler warnings, formatting issues, or test failures.

**Step 3: Commit any fixes**

```
git add -A
git commit -m "Fix precommit issues"
```
