# Memory Vaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rich-text Memory Vaults to families — vaults containing memories with Trix editor, @mentions, and album photo embeds.

**Architecture:** New `Ancestry.Memories` context with Vault/Memory/MemoryMention schemas. Trix v2 editor integrated via JS hook with custom @mention support. ContentParser extracts references from HTML using LazyHTML. ContentRenderer sanitizes and transforms HTML for display with CSS-only hover cards.

**Tech Stack:** Phoenix LiveView, Ecto.Multi, Trix v2 (npm), LazyHTML, HtmlSanitizeEx, PubSub

**Spec:** `docs/plans/2026-04-09-memory-vaults-design.md`

---

## File Structure

### New files

```
# Schemas
lib/ancestry/memories.ex                              # Context module
lib/ancestry/memories/vault.ex                         # Vault schema
lib/ancestry/memories/memory.ex                        # Memory schema
lib/ancestry/memories/memory_mention.ex                # MemoryMention join schema
lib/ancestry/memories/content_parser.ex                # Extract refs from Trix HTML
lib/ancestry/memories/content_renderer.ex              # Sanitize + transform HTML for display

# LiveViews & Components
lib/web/live/vault_live/show.ex                        # Vault show page
lib/web/live/vault_live/show.html.heex                 # Vault show template
lib/web/live/memory_live/form.ex                       # Memory new/edit (includes inline album photo picker)
lib/web/live/memory_live/form.html.heex                # Memory form template

# JS
assets/js/trix_editor.js                               # TrixEditor hook

# Migrations
priv/repo/migrations/*_create_memory_vaults.exs
priv/repo/migrations/*_create_memories.exs
priv/repo/migrations/*_create_memory_mentions.exs

# Tests
test/ancestry/memories_test.exs                        # Context tests
test/ancestry/memories/content_parser_test.exs          # Parser tests
test/ancestry/memories/content_renderer_test.exs        # Renderer tests
test/user_flows/memory_vault_crud_test.exs              # User flow tests
```

### Modified files

```
lib/web/router.ex                                      # Add vault/memory routes
lib/web/live/family_live/show.ex                        # Add vault section + modal
lib/web/live/family_live/show.html.heex                 # Vault cards + creation modal
assets/js/app.js                                        # Register TrixEditor hook
assets/css/app.css                                      # Import Trix CSS + hover card styles
assets/package.json                                     # Add trix dependency
test/support/factory.ex                                 # Add vault/memory/mention factories
```

---

## Task 1: Database Migrations

**Files:**
- Create: `priv/repo/migrations/*_create_memory_vaults.exs`
- Create: `priv/repo/migrations/*_create_memories.exs`
- Create: `priv/repo/migrations/*_create_memory_mentions.exs`

- [ ] **Step 1: Generate the memory_vaults migration**

```bash
mix ecto.gen.migration create_memory_vaults
```

Edit the generated file:

```elixir
defmodule Ancestry.Repo.Migrations.CreateMemoryVaults do
  use Ecto.Migration

  def change do
    create table(:memory_vaults) do
      add :name, :string, null: false
      add :family_id, references(:families, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:memory_vaults, [:family_id])
  end
end
```

- [ ] **Step 2: Generate the memories migration**

```bash
mix ecto.gen.migration create_memories
```

Edit the generated file:

```elixir
defmodule Ancestry.Repo.Migrations.CreateMemories do
  use Ecto.Migration

  def change do
    create table(:memories) do
      add :name, :string, null: false
      add :content, :text
      add :description, :string
      add :cover_photo_id, references(:photos, on_delete: :nilify_all)
      add :memory_vault_id, references(:memory_vaults, on_delete: :delete_all), null: false
      add :inserted_by, references(:accounts, on_delete: :nilify_all)

      timestamps()
    end

    create index(:memories, [:memory_vault_id])
    create index(:memories, [:cover_photo_id])
    create index(:memories, [:inserted_by])
  end
end
```

- [ ] **Step 3: Generate the memory_mentions migration**

```bash
mix ecto.gen.migration create_memory_mentions
```

Edit the generated file:

```elixir
defmodule Ancestry.Repo.Migrations.CreateMemoryMentions do
  use Ecto.Migration

  def change do
    create table(:memory_mentions) do
      add :memory_id, references(:memories, on_delete: :delete_all), null: false
      add :person_id, references(:persons, on_delete: :delete_all), null: false
    end

    create unique_index(:memory_mentions, [:memory_id, :person_id])
    create index(:memory_mentions, [:person_id])
  end
end
```

- [ ] **Step 4: Run migrations**

```bash
mix ecto.migrate
```

Expected: all 3 migrations run successfully.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/migrations/*_create_memory_vaults.exs priv/repo/migrations/*_create_memories.exs priv/repo/migrations/*_create_memory_mentions.exs
git commit -m "feat: add memory_vaults, memories, and memory_mentions tables"
```

---

## Task 2: Schemas

**Files:**
- Create: `lib/ancestry/memories/vault.ex`
- Create: `lib/ancestry/memories/memory.ex`
- Create: `lib/ancestry/memories/memory_mention.ex`

- [ ] **Step 1: Create the Vault schema**

```elixir
# lib/ancestry/memories/vault.ex
defmodule Ancestry.Memories.Vault do
  use Ecto.Schema
  import Ecto.Changeset

  schema "memory_vaults" do
    field :name, :string
    field :memory_count, :integer, virtual: true, default: 0

    belongs_to :family, Ancestry.Families.Family
    has_many :memories, Ancestry.Memories.Memory, foreign_key: :memory_vault_id

    timestamps()
  end

  def changeset(vault, attrs) do
    vault
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:family_id)
  end
end
```

- [ ] **Step 2: Create the Memory schema**

```elixir
# lib/ancestry/memories/memory.ex
defmodule Ancestry.Memories.Memory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "memories" do
    field :name, :string
    field :content, :string
    field :description, :string

    belongs_to :cover_photo, Ancestry.Galleries.Photo
    belongs_to :memory_vault, Ancestry.Memories.Vault
    belongs_to :account, Ancestry.Identity.Account, foreign_key: :inserted_by

    has_many :memory_mentions, Ancestry.Memories.MemoryMention
    has_many :mentioned_people, through: [:memory_mentions, :person]

    timestamps()
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:name, :content, :cover_photo_id, :memory_vault_id, :inserted_by])
    |> validate_required([:name, :memory_vault_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:memory_vault_id)
    |> foreign_key_constraint(:cover_photo_id)
    |> foreign_key_constraint(:inserted_by)
  end
end
```

- [ ] **Step 3: Create the MemoryMention schema**

```elixir
# lib/ancestry/memories/memory_mention.ex
defmodule Ancestry.Memories.MemoryMention do
  use Ecto.Schema
  import Ecto.Changeset

  schema "memory_mentions" do
    belongs_to :memory, Ancestry.Memories.Memory
    belongs_to :person, Ancestry.People.Person
  end

  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [:memory_id, :person_id])
    |> validate_required([:memory_id, :person_id])
    |> foreign_key_constraint(:memory_id)
    |> foreign_key_constraint(:person_id)
    |> unique_constraint([:memory_id, :person_id])
  end
end
```

- [ ] **Step 4: Verify schemas compile**

```bash
mix compile --warnings-as-errors
```

Expected: compilation succeeds with no warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/memories/vault.ex lib/ancestry/memories/memory.ex lib/ancestry/memories/memory_mention.ex
git commit -m "feat: add Vault, Memory, and MemoryMention schemas"
```

---

## Task 3: Factories

**Files:**
- Modify: `test/support/factory.ex`

- [ ] **Step 1: Add vault, memory, and memory_mention factories**

Add these factory definitions to `test/support/factory.ex`:

```elixir
def vault_factory do
  %Ancestry.Memories.Vault{
    name: sequence(:vault_name, &"Vault #{&1}"),
    family: build(:family)
  }
end

def memory_factory do
  %Ancestry.Memories.Memory{
    name: sequence(:memory_name, &"Memory #{&1}"),
    content: "<div>A test memory</div>",
    description: "A test memory",
    memory_vault: build(:vault)
  }
end

def memory_mention_factory do
  %Ancestry.Memories.MemoryMention{
    memory: build(:memory),
    person: build(:person)
  }
end
```

- [ ] **Step 2: Verify factories compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add test/support/factory.ex
git commit -m "feat: add vault, memory, and memory_mention factories"
```

---

## Task 4: Context — Vault CRUD

**Files:**
- Create: `lib/ancestry/memories.ex`
- Create: `test/ancestry/memories_test.exs`

- [ ] **Step 1: Write failing tests for vault CRUD**

```elixir
# test/ancestry/memories_test.exs
defmodule Ancestry.MemoriesTest do
  use Ancestry.DataCase

  alias Ancestry.Memories
  alias Ancestry.Memories.Vault

  describe "vaults" do
    setup do
      org = insert(:organization)
      family = insert(:family, organization: org)
      %{org: org, family: family}
    end

    test "list_vaults/1 returns vaults for a family ordered by inserted_at desc", %{family: family} do
      vault1 = insert(:vault, family: family)
      vault2 = insert(:vault, family: family)

      result = Memories.list_vaults(family.id)
      assert [v2, v1] = result
      assert v2.id == vault2.id
      assert v1.id == vault1.id
    end

    test "list_vaults/1 does not return vaults from other families", %{family: family} do
      insert(:vault, family: family)
      other_family = insert(:family)
      insert(:vault, family: other_family)

      assert length(Memories.list_vaults(family.id)) == 1
    end

    test "get_vault!/1 returns the vault", %{family: family} do
      vault = insert(:vault, family: family)
      assert Memories.get_vault!(vault.id).id == vault.id
    end

    test "create_vault/2 with valid data creates a vault", %{family: family} do
      assert {:ok, %Vault{} = vault} = Memories.create_vault(family, %{name: "My Memories"})
      assert vault.name == "My Memories"
      assert vault.family_id == family.id
    end

    test "create_vault/2 with blank name returns error changeset", %{family: family} do
      assert {:error, %Ecto.Changeset{}} = Memories.create_vault(family, %{name: ""})
    end

    test "update_vault/2 updates the vault name", %{family: family} do
      vault = insert(:vault, family: family)
      assert {:ok, updated} = Memories.update_vault(vault, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "delete_vault/1 deletes the vault", %{family: family} do
      vault = insert(:vault, family: family)
      assert {:ok, _} = Memories.delete_vault(vault)
      assert_raise Ecto.NoResultsError, fn -> Memories.get_vault!(vault.id) end
    end

    test "change_vault/2 returns a changeset", %{family: family} do
      vault = insert(:vault, family: family)
      assert %Ecto.Changeset{} = Memories.change_vault(vault, %{})
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/ancestry/memories_test.exs
```

Expected: FAIL — `Ancestry.Memories` module not found.

- [ ] **Step 3: Implement the Memories context with vault CRUD**

```elixir
# lib/ancestry/memories.ex
defmodule Ancestry.Memories do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.Memories.Vault

  # --- Vaults ---

  def list_vaults(family_id) do
    Repo.all(
      from v in Vault,
        where: v.family_id == ^family_id,
        left_join: m in assoc(v, :memories),
        group_by: v.id,
        select_merge: %{memory_count: count(m.id)},
        order_by: [desc: v.inserted_at]
    )
  end

  def get_vault!(id) do
    Repo.get!(Vault, id)
  end

  @doc "Returns a count of memories in the vault."
  def memory_count(vault_id) do
    Repo.aggregate(
      from(m in Memory, where: m.memory_vault_id == ^vault_id),
      :count
    )
  end

  def create_vault(family, attrs) do
    %Vault{family_id: family.id}
    |> Vault.changeset(attrs)
    |> Repo.insert()
  end

  def update_vault(%Vault{} = vault, attrs) do
    vault
    |> Vault.changeset(attrs)
    |> Repo.update()
  end

  def delete_vault(%Vault{} = vault) do
    Repo.delete(vault)
  end

  def change_vault(%Vault{} = vault, attrs \\ %{}) do
    Vault.changeset(vault, attrs)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/ancestry/memories_test.exs
```

Expected: all vault tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/memories.ex test/ancestry/memories_test.exs
git commit -m "feat: add Memories context with vault CRUD"
```

---

## Task 5: ContentParser

**Files:**
- Create: `lib/ancestry/memories/content_parser.ex`
- Create: `test/ancestry/memories/content_parser_test.exs`

- [ ] **Step 1: Write failing tests for ContentParser**

```elixir
# test/ancestry/memories/content_parser_test.exs
defmodule Ancestry.Memories.ContentParserTest do
  use ExUnit.Case, async: true

  alias Ancestry.Memories.ContentParser

  describe "parse/1" do
    test "returns empty results for nil content" do
      assert ContentParser.parse(nil) == {"", [], []}
    end

    test "returns empty results for empty string" do
      assert ContentParser.parse("") == {"", [], []}
    end

    test "extracts plain text description from HTML" do
      html = "<div>Hello world, this is a memory.</div>"
      {description, _, _} = ContentParser.parse(html)
      assert description == "Hello world, this is a memory."
    end

    test "truncates description to 100 characters" do
      long_text = String.duplicate("a", 150)
      html = "<div>#{long_text}</div>"
      {description, _, _} = ContentParser.parse(html)
      assert String.length(description) == 100
    end

    test "strips image figure elements from description" do
      html = """
      <div>Before image.</div>
      <figure data-trix-attachment='{"contentType":"application/vnd.memory-photo"}'>
        <img data-photo-id="7" src="/uploads/thumb.jpg" />
      </figure>
      <div>After image.</div>
      """

      {description, _, _} = ContentParser.parse(html)
      assert description =~ "Before image."
      assert description =~ "After image."
      refute description =~ "thumb.jpg"
    end

    test "extracts person IDs from mention attachments" do
      html = """
      <div>Hello
        <figure data-trix-attachment='{"contentType":"application/vnd.memory-mention"}'>
          <span data-person-id="42">@John Smith</span>
        </figure>
        and
        <figure data-trix-attachment='{"contentType":"application/vnd.memory-mention"}'>
          <span data-person-id="99">@Jane Doe</span>
        </figure>
      </div>
      """

      {_, person_ids, _} = ContentParser.parse(html)
      assert Enum.sort(person_ids) == [42, 99]
    end

    test "extracts photo IDs from photo attachments" do
      html = """
      <figure data-trix-attachment='{"contentType":"application/vnd.memory-photo"}'>
        <img data-photo-id="7" src="/uploads/thumb.jpg" />
      </figure>
      <figure data-trix-attachment='{"contentType":"application/vnd.memory-photo"}'>
        <img data-photo-id="12" src="/uploads/thumb2.jpg" />
      </figure>
      """

      {_, _, photo_ids} = ContentParser.parse(html)
      assert Enum.sort(photo_ids) == [7, 12]
    end

    test "deduplicates IDs" do
      html = """
      <figure data-trix-attachment='{"contentType":"application/vnd.memory-mention"}'>
        <span data-person-id="42">@John</span>
      </figure>
      <figure data-trix-attachment='{"contentType":"application/vnd.memory-mention"}'>
        <span data-person-id="42">@John</span>
      </figure>
      """

      {_, person_ids, _} = ContentParser.parse(html)
      assert person_ids == [42]
    end

    test "handles malformed HTML gracefully" do
      html = "<div>unclosed <strong>bold"
      {description, person_ids, photo_ids} = ContentParser.parse(html)
      assert is_binary(description)
      assert person_ids == []
      assert photo_ids == []
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/ancestry/memories/content_parser_test.exs
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement ContentParser**

Check the LazyHTML API first — read `deps/lazy_html/lib/lazy_html.ex` to understand exact function signatures. Then implement:

```elixir
# lib/ancestry/memories/content_parser.ex
defmodule Ancestry.Memories.ContentParser do
  @moduledoc false

  @doc """
  Parses Trix HTML content and returns {description, person_ids, photo_ids}.

  - description: plain text, first 100 chars, stripped of HTML and image refs
  - person_ids: list of integer person IDs from mention attachments
  - photo_ids: list of integer photo IDs from photo attachments
  """
  def parse(nil), do: {"", [], []}
  def parse(""), do: {"", [], []}

  def parse(html) when is_binary(html) do
    # IMPORTANT: Read deps/lazy_html/lib/lazy_html.ex first to confirm the API.
    # LazyHTML.attribute/2 returns a list of values, not a single value.
    # LazyHTML.query/2 returns a LazyHTML struct (list of nodes), not an Enum.
    # Adapt the calls below to match the actual API signatures.
    doc = LazyHTML.from_document(html)

    person_ids = extract_ids(doc, "span[data-person-id]", "data-person-id")
    photo_ids = extract_ids(doc, "img[data-photo-id]", "data-photo-id")
    description = build_description(doc)

    {description, person_ids, photo_ids}
  end

  defp extract_ids(doc, selector, attr) do
    doc
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute(attr)
    |> Enum.map(&String.to_integer/1)
    |> Enum.uniq()
  end

  defp build_description(doc) do
    # Remove figure elements before extracting text so image refs
    # and mention display names inside figures are excluded.
    # If LazyHTML doesn't support node removal, extract text and
    # post-process with regex to strip @mentions.
    doc
    |> LazyHTML.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 100)
  end
end
```

**Note:** If `LazyHTML` doesn't support CSS selectors or the API doesn't match, fall back to `Floki` (add `{:floki, "~> 0.37"}` to mix.exs). With Floki the pattern is: `Floki.parse_fragment!(html) |> Floki.find(selector) |> Floki.attribute(attr)`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/ancestry/memories/content_parser_test.exs
```

Expected: all ContentParser tests PASS. If LazyHTML API doesn't match, adapt implementation.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/memories/content_parser.ex test/ancestry/memories/content_parser_test.exs
git commit -m "feat: add ContentParser to extract refs from Trix HTML"
```

---

## Task 6: Context — Memory CRUD with Ecto.Multi

**Files:**
- Modify: `lib/ancestry/memories.ex`
- Modify: `test/ancestry/memories_test.exs`

- [ ] **Step 1: Write failing tests for memory CRUD**

Add to `test/ancestry/memories_test.exs`:

```elixir
describe "memories" do
  setup do
    org = insert(:organization)
    family = insert(:family, organization: org)
    vault = insert(:vault, family: family)
    account = insert(:account)
    person = insert(:person, organization: org)
    gallery = insert(:gallery, family: family)
    photo = insert(:photo, gallery: gallery)
    %{org: org, family: family, vault: vault, account: account, person: person, photo: photo}
  end

  test "list_memories/1 returns memories ordered by inserted_at desc", %{vault: vault, account: account} do
    m1 = insert(:memory, memory_vault: vault, account: account)
    m2 = insert(:memory, memory_vault: vault, account: account)

    result = Memories.list_memories(vault.id)
    assert [r2, r1] = result
    assert r2.id == m2.id
    assert r1.id == m1.id
  end

  test "get_memory!/1 returns the memory with preloads", %{vault: vault, account: account} do
    memory = insert(:memory, memory_vault: vault, account: account)
    result = Memories.get_memory!(memory.id)
    assert result.id == memory.id
  end

  test "create_memory/3 creates a memory and generates description", %{vault: vault, account: account} do
    attrs = %{name: "Summer Trip", content: "<div>We went to the beach.</div>"}

    assert {:ok, memory} = Memories.create_memory(vault, account, attrs)
    assert memory.name == "Summer Trip"
    assert memory.description == "We went to the beach."
    assert memory.inserted_by == account.id
  end

  test "create_memory/3 syncs mentions from content", %{vault: vault, account: account, person: person, org: org} do
    html = """
    <div>Remember
      <figure data-trix-attachment='{"contentType":"application/vnd.memory-mention"}'>
        <span data-person-id="#{person.id}">@#{person.given_name}</span>
      </figure>
    </div>
    """

    assert {:ok, memory} = Memories.create_memory(vault, account, %{name: "Test", content: html})
    memory = Memories.get_memory!(memory.id)
    assert length(memory.memory_mentions) == 1
    assert hd(memory.memory_mentions).person_id == person.id
  end

  test "create_memory/3 drops mentions for people outside the organization", %{vault: vault, account: account} do
    other_org = insert(:organization)
    other_person = insert(:person, organization: other_org)

    html = """
    <figure data-trix-attachment='{"contentType":"application/vnd.memory-mention"}'>
      <span data-person-id="#{other_person.id}">@Outsider</span>
    </figure>
    """

    assert {:ok, memory} = Memories.create_memory(vault, account, %{name: "Test", content: html})
    memory = Memories.get_memory!(memory.id)
    assert memory.memory_mentions == []
  end

  test "create_memory/3 with blank name returns error", %{vault: vault, account: account} do
    assert {:error, %Ecto.Changeset{}} =
             Memories.create_memory(vault, account, %{name: ""})
  end

  test "update_memory/2 updates and re-syncs mentions", %{vault: vault, account: account, person: person, org: org} do
    {:ok, memory} = Memories.create_memory(vault, account, %{name: "Test", content: "<div>Hello</div>"})

    new_html = """
    <figure data-trix-attachment='{"contentType":"application/vnd.memory-mention"}'>
      <span data-person-id="#{person.id}">@#{person.given_name}</span>
    </figure>
    """

    assert {:ok, updated} = Memories.update_memory(memory, %{content: new_html})
    updated = Memories.get_memory!(updated.id)
    assert length(updated.memory_mentions) == 1
  end

  test "delete_memory/1 deletes the memory", %{vault: vault, account: account} do
    {:ok, memory} = Memories.create_memory(vault, account, %{name: "Test", content: ""})
    assert {:ok, _} = Memories.delete_memory(memory)
    assert_raise Ecto.NoResultsError, fn -> Memories.get_memory!(memory.id) end
  end

  test "delete_vault/1 cascades to memories", %{vault: vault, account: account} do
    {:ok, memory} = Memories.create_memory(vault, account, %{name: "Test", content: ""})
    Memories.delete_vault(vault)
    assert_raise Ecto.NoResultsError, fn -> Memories.get_memory!(memory.id) end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/ancestry/memories_test.exs
```

Expected: FAIL — memory functions not defined.

- [ ] **Step 3: Implement memory CRUD in the context**

Add to `lib/ancestry/memories.ex`:

```elixir
alias Ecto.Multi
alias Ancestry.Memories.Memory
alias Ancestry.Memories.MemoryMention
alias Ancestry.Memories.ContentParser
alias Ancestry.People.Person

# --- Memories ---

def list_memories(vault_id) do
  Repo.all(
    from m in Memory,
      where: m.memory_vault_id == ^vault_id,
      order_by: [desc: m.inserted_at],
      preload: [:cover_photo]
  )
end

def get_memory!(id) do
  Repo.get!(Memory, id)
  |> Repo.preload([:cover_photo, memory_mentions: :person])
end

def create_memory(%Vault{} = vault, account, attrs) do
  vault = Repo.preload(vault, :family)
  org_id = vault.family.organization_id
  attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  content = Map.get(attrs, "content", "")
  {description, person_ids, _photo_ids} = ContentParser.parse(content)

  valid_person_ids = filter_org_person_ids(person_ids, org_id)

  Multi.new()
  |> Multi.insert(:memory, fn _ ->
    %Memory{memory_vault_id: vault.id, inserted_by: account.id}
    |> Memory.changeset(attrs)
    |> Ecto.Changeset.put_change(:description, description)
  end)
  |> Multi.insert_all(:mentions, MemoryMention, fn %{memory: memory} ->
    Enum.map(valid_person_ids, fn pid ->
      %{memory_id: memory.id, person_id: pid}
    end)
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{memory: memory}} -> {:ok, memory}
    {:error, _failed_operation, failed_value, _changes} -> {:error, failed_value}
  end
end

def update_memory(%Memory{} = memory, attrs) do
  memory = Repo.preload(memory, memory_vault: :family)
  org_id = memory.memory_vault.family.organization_id
  attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  content = Map.get(attrs, "content", memory.content || "")
  {description, person_ids, _photo_ids} = ContentParser.parse(content)

  valid_person_ids = filter_org_person_ids(person_ids, org_id)

  Multi.new()
  |> Multi.update(:memory, fn _ ->
    memory
    |> Memory.changeset(attrs)
    |> Ecto.Changeset.put_change(:description, description)
  end)
  |> Multi.delete_all(:delete_mentions, fn _ ->
    from mm in MemoryMention, where: mm.memory_id == ^memory.id
  end)
  |> Multi.insert_all(:mentions, MemoryMention, fn _ ->
    Enum.map(valid_person_ids, fn pid ->
      %{memory_id: memory.id, person_id: pid}
    end)
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{memory: memory}} -> {:ok, memory}
    {:error, _failed_operation, failed_value, _changes} -> {:error, failed_value}
  end
end

def delete_memory(%Memory{} = memory) do
  Repo.delete(memory)
end

def change_memory(%Memory{} = memory, attrs \\ %{}) do
  Memory.changeset(memory, attrs)
end

defp filter_org_person_ids(person_ids, org_id) when person_ids == [], do: []

defp filter_org_person_ids(person_ids, org_id) do
  Repo.all(
    from p in Person,
      where: p.id in ^person_ids and p.organization_id == ^org_id,
      select: p.id
  )
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/ancestry/memories_test.exs
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/memories.ex test/ancestry/memories_test.exs
git commit -m "feat: add memory CRUD with Ecto.Multi and mention sync"
```

---

## Task 7: PubSub for Memories

**Files:**
- Modify: `lib/ancestry/memories.ex`

- [ ] **Step 1: Add PubSub broadcasts to create/update/delete memory**

After the `{:ok, memory}` return in `create_memory`, `update_memory`, and `delete_memory`, broadcast events:

```elixir
# In create_memory, replace the success case:
{:ok, %{memory: memory}} ->
  Phoenix.PubSub.broadcast(Ancestry.PubSub, "vault:#{vault.id}", {:memory_created, memory})
  {:ok, memory}

# In update_memory, replace the success case:
{:ok, %{memory: memory}} ->
  Phoenix.PubSub.broadcast(Ancestry.PubSub, "vault:#{memory.memory_vault_id}", {:memory_updated, memory})
  {:ok, memory}

# In delete_memory, wrap with broadcast:
def delete_memory(%Memory{} = memory) do
  case Repo.delete(memory) do
    {:ok, memory} ->
      Phoenix.PubSub.broadcast(Ancestry.PubSub, "vault:#{memory.memory_vault_id}", {:memory_deleted, memory})
      {:ok, memory}

    error ->
      error
  end
end
```

- [ ] **Step 2: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add lib/ancestry/memories.ex
git commit -m "feat: add PubSub broadcasts for memory events"
```

---

## Task 8: ContentRenderer

**Files:**
- Create: `lib/ancestry/memories/content_renderer.ex`
- Create: `test/ancestry/memories/content_renderer_test.exs`

- [ ] **Step 1: Choose a sanitization approach**

Two options — pick the one that works best:

**Option A: `html_sanitize_ex`** — Add `{:html_sanitize_ex, "~> 1.4"}` to `mix.exs` and run `mix deps.get`. Use `HtmlSanitizeEx.basic_html/1` for baseline sanitization, then strip remaining disallowed attributes via regex. Check the hex docs for custom scrubber support.

**Option B: LazyHTML-based sanitizer (no new dep)** — Walk the HTML tree with `LazyHTML`, remove disallowed tags/attributes, serialize back. More work but no new dependency.

Either way, run `mix deps.get` if a new dep was added.

- [ ] **Step 2: Write failing tests for ContentRenderer**

```elixir
# test/ancestry/memories/content_renderer_test.exs
defmodule Ancestry.Memories.ContentRendererTest do
  use Ancestry.DataCase

  alias Ancestry.Memories.ContentRenderer

  describe "render/3" do
    test "returns empty string for nil content" do
      assert ContentRenderer.render(nil, %{}, 1) == ""
    end

    test "sanitizes script tags" do
      html = ~s(<div>Hello</div><script>alert('xss')</script>)
      result = ContentRenderer.render(html, %{}, 1)
      refute result =~ "<script>"
      assert result =~ "Hello"
    end

    test "sanitizes event handler attributes" do
      html = ~s(<div onclick="alert('xss')">Hello</div>)
      result = ContentRenderer.render(html, %{}, 1)
      refute result =~ "onclick"
      assert result =~ "Hello"
    end

    test "preserves allowed formatting tags" do
      html = "<div><strong>Bold</strong> and <em>italic</em></div>"
      result = ContentRenderer.render(html, %{}, 1)
      assert result =~ "<strong>Bold</strong>"
      assert result =~ "<em>italic</em>"
    end

    test "transforms mention figures into links with hover cards" do
      person = insert(:person, given_name: "John", surname: "Smith")

      html = """
      <figure data-trix-attachment='{"contentType":"application/vnd.memory-mention"}'>
        <span data-person-id="#{person.id}">@John Smith</span>
      </figure>
      """

      people_map = %{person.id => person}
      result = ContentRenderer.render(html, people_map, person.organization_id)
      assert result =~ ~s(href="/org/#{person.organization_id}/people/#{person.id}")
      assert result =~ "John Smith"
    end

    test "transforms photo figures into img tags" do
      html = """
      <figure data-trix-attachment='{"contentType":"application/vnd.memory-photo"}'>
        <img data-photo-id="7" src="/old/path.jpg" />
      </figure>
      """

      result = ContentRenderer.render(html, %{}, 1)
      assert result =~ "<img"
      assert result =~ ~s(data-photo-id="7")
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
mix test test/ancestry/memories/content_renderer_test.exs
```

Expected: FAIL — module not found.

- [ ] **Step 4: Implement ContentRenderer**

```elixir
# lib/ancestry/memories/content_renderer.ex
defmodule Ancestry.Memories.ContentRenderer do
  @moduledoc false

  @allowed_tags ~w(div p br strong em del blockquote ul ol li h1 a pre figure figcaption img span)
  @allowed_attrs ~w(href data-person-id data-photo-id data-trix-attachment src class)

  @doc """
  Sanitizes and transforms stored Trix HTML for display.

  - Strips disallowed tags and attributes
  - Transforms mention figures into links with CSS hover cards
  - Transforms photo figures into img tags
  """
  def render(nil, _people_map, _org_id), do: ""
  def render("", _people_map, _org_id), do: ""

  def render(html, people_map, org_id) when is_binary(html) do
    html
    |> sanitize()
    |> transform_mentions(people_map, org_id)
    |> transform_photos()
  end

  defp sanitize(html) do
    # Option A: HtmlSanitizeEx.basic_html(html)
    # Option B: LazyHTML-based allowlist (see design spec Security section for the tag/attr allowlist)
    # The implementer must choose and implement one of these.
    # Minimum: strip <script>, <iframe>, <object>, <embed>, <style>, <link>,
    # and all event handler attributes (onclick, onerror, etc.)
    HtmlSanitizeEx.basic_html(html)
  end

  defp transform_mentions(html, people_map, org_id) when people_map == %{}, do: html

  defp transform_mentions(html, people_map, org_id) do
    # Use regex to find mention spans and replace with links + hover cards
    Regex.replace(
      ~r/<span data-person-id="(\d+)">(@[^<]+)<\/span>/,
      html,
      fn _, id_str, name ->
        id = String.to_integer(id_str)

        case Map.get(people_map, id) do
          nil ->
            name

          person ->
            build_mention_html(person, org_id, name)
        end
      end
    )
  end

  defp transform_photos(html) do
    # Photos are already img tags — just pass through after sanitization
    html
  end

  defp build_mention_html(person, org_id, display_name) do
    photo_html = if person.photo do
      ~s(<img src="#{person_photo_url(person)}" class="w-8 h-8 rounded-full object-cover" />)
    else
      ~s(<div class="w-8 h-8 rounded-full bg-ds-surface-high flex items-center justify-center text-xs font-semibold">#{String.first(person.given_name || "")}</div>)
    end

    years = build_years(person)

    """
    <span class="relative inline-block group">
      <a href="/org/#{org_id}/people/#{person.id}" class="text-ds-primary font-semibold hover:underline">#{display_name}</a>
      <span class="hidden group-hover:block absolute bottom-full left-1/2 -translate-x-1/2 mb-1 z-50 pointer-events-none">
        <span class="flex items-center gap-2 bg-ds-surface-card shadow-ds-ambient rounded-ds-sharp px-3 py-2 whitespace-nowrap">
          #{photo_html}
          <span class="flex flex-col">
            <span class="text-sm font-semibold text-ds-on-surface">#{person.given_name} #{person.surname}</span>
            #{if years != "", do: ~s(<span class="text-xs text-ds-on-surface-variant">#{years}</span>), else: ""}
          </span>
        </span>
      </span>
    </span>
    """
  end

  defp build_years(person) do
    birth = if person.birth_year, do: "#{person.birth_year}", else: nil
    death = if person.death_year, do: "#{person.death_year}", else: nil

    case {birth, death} do
      {nil, nil} -> ""
      {b, nil} -> "b. #{b}"
      {nil, d} -> "d. #{d}"
      {b, d} -> "#{b} - #{d}"
    end
  end

  defp person_photo_url(person) do
    # Use Waffle URL helper
    Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)
  end
end
```

**Note:** `HtmlSanitizeEx.basic_html/1` strips most dangerous elements but may also strip `data-*` attributes and `figure` tags that Trix uses. After sanitization, the mention/photo transforms run on the result, so ensure `data-person-id` and `data-photo-id` attributes survive. If `basic_html` strips them, either sanitize after extracting IDs, or implement a custom scrubber. Read the `HtmlSanitizeEx` hex docs for the custom scrubber API.

- [ ] **Step 5: Run tests to verify they pass**

```bash
mix test test/ancestry/memories/content_renderer_test.exs
```

Expected: all tests PASS. Adapt the sanitization approach if the library API doesn't match.

- [ ] **Step 6: Commit**

```bash
git add lib/ancestry/memories/content_renderer.ex test/ancestry/memories/content_renderer_test.exs mix.exs mix.lock
git commit -m "feat: add ContentRenderer with HTML sanitization and mention transforms"
```

---

## Task 9: Routes

**Files:**
- Modify: `lib/web/router.ex`

- [ ] **Step 1: Add vault and memory routes**

Inside the existing `live_session :organization` block in `lib/web/router.ex`, add after the gallery route:

```elixir
live "/families/:family_id/vaults/:vault_id", VaultLive.Show, :show
live "/families/:family_id/vaults/:vault_id/memories/new", MemoryLive.Form, :new
live "/families/:family_id/vaults/:vault_id/memories/:memory_id", MemoryLive.Form, :edit
```

- [ ] **Step 2: Verify compilation**

```bash
mix compile --warnings-as-errors
```

Expected: warnings about missing `VaultLive.Show` and `MemoryLive.Form` modules (acceptable at this stage — they will be created in subsequent tasks).

- [ ] **Step 3: Commit**

```bash
git add lib/web/router.ex
git commit -m "feat: add vault and memory routes"
```

---

## Task 10: VaultLive.Show

**Files:**
- Create: `lib/web/live/vault_live/show.ex`
- Create: `lib/web/live/vault_live/show.html.heex`

- [ ] **Step 1: Create VaultLive.Show LiveView**

```elixir
# lib/web/live/vault_live/show.ex
defmodule Web.VaultLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Memories

  @impl true
  def mount(%{"family_id" => family_id, "vault_id" => vault_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    vault = Memories.get_vault!(vault_id)

    if vault.family_id != family.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Memories.Vault
    end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "vault:#{vault.id}")
    end

    memories = Memories.list_memories(vault.id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:vault, vault)
     |> assign(:confirm_delete_vault, false)
     |> assign(:confirm_delete_memory, nil)
     |> assign(:has_memories, memories != [])
     |> stream(:memories, memories)}
  end

  @impl true
  def handle_info({:memory_created, memory}, socket) do
    memory = Memories.get_memory!(memory.id)
    {:noreply, stream_insert(socket, :memories, memory, at: 0)}
  end

  def handle_info({:memory_updated, memory}, socket) do
    memory = Memories.get_memory!(memory.id)
    {:noreply, stream_insert(socket, :memories, memory)}
  end

  def handle_info({:memory_deleted, memory}, socket) do
    {:noreply, stream_delete(socket, :memories, memory)}
  end

  @impl true
  def handle_event("request_delete_vault", _, socket) do
    {:noreply, assign(socket, :confirm_delete_vault, true)}
  end

  def handle_event("cancel_delete_vault", _, socket) do
    {:noreply, assign(socket, :confirm_delete_vault, false)}
  end

  def handle_event("confirm_delete_vault", _, socket) do
    {:ok, _} = Memories.delete_vault(socket.assigns.vault)

    {:noreply,
     socket
     |> put_flash(:info, "Vault deleted")
     |> push_navigate(to: ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}")}
  end

  def handle_event("request_delete_memory", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_memory, Memories.get_memory!(id))}
  end

  def handle_event("cancel_delete_memory", _, socket) do
    {:noreply, assign(socket, :confirm_delete_memory, nil)}
  end

  def handle_event("confirm_delete_memory", _, socket) do
    {:ok, _} = Memories.delete_memory(socket.assigns.confirm_delete_memory)

    {:noreply,
     socket
     |> assign(:confirm_delete_memory, nil)
     |> put_flash(:info, "Memory deleted")}
  end
end
```

- [ ] **Step 2: Create the template**

```heex
<%!-- lib/web/live/vault_live/show.html.heex --%>
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <%!-- Header --%>
  <div class="flex items-center justify-between mb-6">
    <div class="flex items-center gap-3">
      <.link
        navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}"}
        class="p-1 rounded text-ds-on-surface-variant hover:text-ds-primary hover:bg-ds-primary/10 transition-colors"
      >
        <.icon name="hero-arrow-left" class="w-5 h-5" />
      </.link>
      <h1 class="text-2xl font-ds-heading font-bold text-ds-on-surface">
        {@vault.name}
      </h1>
    </div>
    <div class="flex items-center gap-2">
      <.link
        navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/vaults/#{@vault.id}/memories/new"}
        class="bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp px-4 py-2 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
      >
        Add Memory
      </.link>
      <button
        phx-click="request_delete_vault"
        class="p-2 rounded text-ds-on-surface-variant hover:text-ds-error hover:bg-ds-error/10 transition-colors"
      >
        <.icon name="hero-trash" class="w-4 h-4" />
      </button>
    </div>
  </div>

  <%!-- Memory Cards Grid --%>
  <div id="memories-grid" phx-update="stream" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
    <div :for={{dom_id, memory} <- @streams.memories} id={dom_id}>
      <.link
        navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/vaults/#{@vault.id}/memories/#{memory.id}"}
        class="block bg-ds-surface-card rounded-ds-sharp shadow-ds-ambient hover:shadow-md transition-shadow overflow-hidden"
      >
        <%= if memory.cover_photo && memory.cover_photo.image do %>
          <div class="w-full h-40 overflow-hidden">
            <img
              src={Ancestry.Uploaders.Photo.url({memory.cover_photo.image, memory.cover_photo}, :large)}
              class="w-full h-full object-cover"
            />
          </div>
        <% end %>
        <div class="p-4">
          <h3 class="font-ds-heading font-bold text-ds-on-surface mb-1 truncate">
            {memory.name}
          </h3>
          <p :if={memory.description} class="text-sm text-ds-on-surface-variant line-clamp-2 mb-2">
            {memory.description}
          </p>
          <time class="text-xs text-ds-on-surface-variant">
            {Calendar.strftime(memory.inserted_at, "%b %d, %Y")}
          </time>
        </div>
      </.link>
    </div>
  </div>

  <%!-- Empty state --%>
  <div :if={not @has_memories} class="text-center py-12">
    <p class="text-ds-on-surface-variant mb-4">No memories yet.</p>
    <.link
      navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/vaults/#{@vault.id}/memories/new"}
      class="text-ds-primary font-semibold hover:underline"
    >
      Create your first memory
    </.link>
  </div>

  <%!-- Delete Vault Confirmation Modal --%>
  <%= if @confirm_delete_vault do %>
    <div
      class="fixed inset-0 z-50 flex items-end lg:items-center justify-center"
      phx-window-keydown="cancel_delete_vault"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_delete_vault" />
      <div
        id="confirm-delete-vault-modal"
        class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp p-8"
        role="dialog"
        aria-modal="true"
        phx-mounted={JS.focus_first()}
      >
        <h2 class="text-xl font-ds-heading font-bold text-ds-on-surface mb-2">Delete Vault</h2>
        <p class="text-ds-on-surface-variant mb-6 font-ds-body">
          Delete <span class="font-semibold">"{@vault.name}"</span>? All memories will be permanently removed. This cannot be undone.
        </p>
        <div class="flex gap-3">
          <button
            phx-click="confirm_delete_vault"
            class="flex-1 bg-ds-error text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:opacity-90 transition-opacity"
          >
            Delete
          </button>
          <button
            phx-click="cancel_delete_vault"
            class="flex-1 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  <% end %>
</Layouts.app>
```

- [ ] **Step 3: Verify it compiles and the page loads**

```bash
mix compile --warnings-as-errors
```

Start the dev server and navigate to a vault URL to verify the page renders.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/vault_live/show.ex lib/web/live/vault_live/show.html.heex
git commit -m "feat: add VaultLive.Show with memory card grid"
```

---

## Task 11: FamilyLive.Show — Vault Section + Creation Modal

**Files:**
- Modify: `lib/web/live/family_live/show.ex`
- Modify: `lib/web/live/family_live/show.html.heex`

- [ ] **Step 1: Add vault state and event handlers to FamilyLive.Show**

In `lib/web/live/family_live/show.ex`:

**In mount/3**, add after the galleries assign:

```elixir
|> assign(:vaults, Memories.list_vaults(family_id))
|> assign(:show_new_vault_modal, false)
|> assign(:vault_form, to_form(Memories.change_vault(%Vault{})))
```

Add the alias at the top:

```elixir
alias Ancestry.Memories
alias Ancestry.Memories.Vault
```

**Add event handlers:**

```elixir
def handle_event("open_new_vault_modal", _, socket) do
  {:noreply,
   socket
   |> assign(:show_new_vault_modal, true)
   |> assign(:vault_form, to_form(Memories.change_vault(%Vault{})))}
end

def handle_event("close_new_vault_modal", _, socket) do
  {:noreply, assign(socket, :show_new_vault_modal, false)}
end

def handle_event("validate_vault", %{"vault" => params}, socket) do
  changeset =
    %Vault{}
    |> Memories.change_vault(params)
    |> Map.put(:action, :validate)

  {:noreply, assign(socket, :vault_form, to_form(changeset))}
end

def handle_event("save_vault", %{"vault" => params}, socket) do
  case Memories.create_vault(socket.assigns.family, params) do
    {:ok, _vault} ->
      vaults = Memories.list_vaults(socket.assigns.family.id)

      {:noreply,
       socket
       |> assign(:show_new_vault_modal, false)
       |> assign(:vaults, vaults)}

    {:error, changeset} ->
      {:noreply, assign(socket, :vault_form, to_form(changeset))}
  end
end
```

- [ ] **Step 2: Add vault section and modal to the template**

In `lib/web/live/family_live/show.html.heex`, add the Memory Vaults section **above** the galleries section. Find the galleries section and insert before it:

```heex
<%!-- Memory Vaults Section --%>
<div class="mb-8">
  <div class="flex items-center justify-between mb-4">
    <h2 class="text-lg font-ds-heading font-bold text-ds-on-surface">Memory Vaults</h2>
    <button
      phx-click="open_new_vault_modal"
      class="p-1 rounded text-ds-on-surface-variant hover:text-ds-primary hover:bg-ds-primary/10 transition-colors"
    >
      <.icon name="hero-plus" class="w-5 h-5" />
    </button>
  </div>

  <%= if @vaults == [] do %>
    <p class="text-sm text-ds-on-surface-variant">No memory vaults yet.</p>
  <% else %>
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <.link
        :for={vault <- @vaults}
        navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/vaults/#{vault.id}"}
        class="block bg-ds-surface-card rounded-ds-sharp shadow-ds-ambient hover:shadow-md transition-shadow p-4"
      >
        <h3 class="font-ds-heading font-bold text-ds-on-surface truncate">{vault.name}</h3>
        <p class="text-xs text-ds-on-surface-variant mt-1">
          {vault.memory_count} memories
        </p>
      </.link>
    </div>
  <% end %>
</div>
```

Add the vault creation modal at the bottom of the template (before any closing tags), using the same pattern as the gallery modal:

```heex
<%!-- New Vault Modal --%>
<%= if @show_new_vault_modal do %>
  <div
    class="fixed inset-0 z-50 flex items-end lg:items-center justify-center"
    phx-window-keydown="close_new_vault_modal"
    phx-key="Escape"
  >
    <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="close_new_vault_modal" />
    <div
      id="new-vault-modal"
      class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp p-8"
      role="dialog"
      aria-modal="true"
      aria-labelledby="new-vault-title"
      phx-mounted={JS.focus_first()}
    >
      <h2 id="new-vault-title" class="text-xl font-ds-heading font-bold text-ds-on-surface mb-6">
        New Memory Vault
      </h2>
      <.form for={@vault_form} id="new-vault-form" phx-submit="save_vault" phx-change="validate_vault">
        <.input field={@vault_form[:name]} label="Vault name" placeholder="e.g. Summer Memories" autofocus />
        <div class="flex gap-3 mt-6">
          <button
            type="submit"
            class="flex-1 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
          >
            Create
          </button>
          <button
            type="button"
            phx-click="close_new_vault_modal"
            class="flex-1 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
          >
            Cancel
          </button>
        </div>
      </.form>
    </div>
  </div>
<% end %>
```

- [ ] **Step 3: Verify compilation and test the modal**

```bash
mix compile --warnings-as-errors
```

Start the dev server, navigate to a family page, and verify the vault section appears and the modal opens/closes.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/family_live/show.ex lib/web/live/family_live/show.html.heex
git commit -m "feat: add memory vaults section and creation modal to family show"
```

---

## Task 12: Install Trix + JS Hook Setup

**Files:**
- Modify: `assets/package.json`
- Create: `assets/js/trix_editor.js`
- Modify: `assets/js/app.js`
- Modify: `assets/css/app.css`

- [ ] **Step 1: Install trix npm package**

```bash
cd assets && npm install trix && cd ..
```

- [ ] **Step 2: Create the TrixEditor hook (basic — no mentions yet)**

```javascript
// assets/js/trix_editor.js
import "trix"

const TrixEditor = {
  mounted() {
    const editor = this.el.querySelector("trix-editor")
    if (!editor) return

    this.editor = editor

    // Block file uploads
    this.el.addEventListener("trix-file-accept", (e) => {
      e.preventDefault()
    })

    // Sync content to hidden input and push to LiveView
    this.el.addEventListener("trix-change", () => {
      const input = this.el.querySelector("input[type=hidden]")
      if (input) {
        input.value = editor.editor.getDocument().toString() !== "\n"
          ? editor.innerHTML
          : ""
        input.dispatchEvent(new Event("input", { bubbles: true }))
      }
    })

    // Handle photo insertion from LiveView
    this.handleEvent("insert_photo", ({ url, photo_id }) => {
      const attachment = new Trix.Attachment({
        contentType: "application/vnd.memory-photo",
        content: `<img data-photo-id="${photo_id}" src="${url}" class="max-w-full rounded" />`,
      })
      editor.editor.insertAttachment(attachment)
    })
  },

  destroyed() {
    // Cleanup handled by element removal
  }
}

export { TrixEditor }
```

- [ ] **Step 3: Register the hook in app.js**

In `assets/js/app.js`, add the import and register:

```javascript
import { TrixEditor } from "./trix_editor"
```

Add `TrixEditor` to the hooks object in the LiveSocket constructor:

```javascript
hooks: { ...colocatedHooks, FuzzyFilter, TreeConnector, PhotoTagger, PersonHighlight, Swipe, TrixEditor },
```

- [ ] **Step 4: Vendorize and import Trix CSS**

The Tailwind standalone CLI cannot resolve `node_modules` imports. Copy Trix CSS to the vendor directory (matching the existing pattern with `animate.css`):

```bash
cp assets/node_modules/trix/dist/trix.css assets/vendor/trix.css
```

Then add to `assets/css/app.css` (after the animate.css import):

```css
@import "../vendor/trix.css";
```

- [ ] **Step 5: Verify the build works**

```bash
cd assets && npx esbuild js/app.js --bundle --outdir=../priv/static/assets --loader:.css=css 2>&1 | head -5 && cd ..
```

Or simply start the dev server and check for build errors.

- [ ] **Step 6: Commit**

```bash
git add assets/package.json assets/package-lock.json assets/js/trix_editor.js assets/js/app.js assets/css/app.css assets/vendor/trix.css
git commit -m "feat: install Trix v2 and create basic TrixEditor hook"
```

---

## Task 13: MemoryLive.Form (New/Edit)

**Files:**
- Create: `lib/web/live/memory_live/form.ex`
- Create: `lib/web/live/memory_live/form.html.heex`

- [ ] **Step 1: Create MemoryLive.Form LiveView**

```elixir
# lib/web/live/memory_live/form.ex
defmodule Web.MemoryLive.Form do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.Memories
  alias Ancestry.Memories.Memory
  alias Ancestry.People

  @impl true
  def mount(%{"family_id" => family_id, "vault_id" => vault_id} = params, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    vault = Memories.get_vault!(vault_id)

    if vault.family_id != family.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Memories.Vault
    end

    galleries = Galleries.list_galleries(family_id)

    socket =
      socket
      |> assign(:family, family)
      |> assign(:vault, vault)
      |> assign(:galleries, galleries)
      |> assign(:cover_photo, nil)
      |> assign(:show_photo_picker, false)
      |> assign(:picker_mode, nil)
      |> assign(:picker_gallery, nil)
      |> assign(:picker_photos, [])
      |> assign(:confirm_delete, false)
      |> assign(:mention_results, [])

    socket = load_memory(socket, params)

    {:ok, socket}
  end

  defp load_memory(socket, %{"memory_id" => memory_id}) do
    memory = Memories.get_memory!(memory_id)

    if memory.memory_vault_id != socket.assigns.vault.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Memories.Memory
    end

    cover_photo = memory.cover_photo

    socket
    |> assign(:memory, memory)
    |> assign(:cover_photo, cover_photo)
    |> assign(:form, to_form(Memories.change_memory(memory, %{})))
  end

  defp load_memory(socket, _params) do
    socket
    |> assign(:memory, nil)
    |> assign(:form, to_form(Memories.change_memory(%Memory{}, %{})))
  end

  @impl true
  def handle_event("validate", %{"memory" => params}, socket) do
    changeset =
      (socket.assigns.memory || %Memory{})
      |> Memories.change_memory(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"memory" => params}, socket) do
    params = maybe_put_cover_photo(params, socket.assigns.cover_photo)

    case socket.assigns.live_action do
      :new -> save_new(socket, params)
      :edit -> save_edit(socket, params)
    end
  end

  defp save_new(socket, params) do
    case Memories.create_memory(socket.assigns.vault, socket.assigns.current_scope.account, params) do
      {:ok, _memory} ->
        {:noreply,
         socket
         |> put_flash(:info, "Memory created")
         |> push_navigate(to: vault_path(socket))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_edit(socket, params) do
    case Memories.update_memory(socket.assigns.memory, params) do
      {:ok, _memory} ->
        {:noreply,
         socket
         |> put_flash(:info, "Memory updated")
         |> push_navigate(to: vault_path(socket))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp maybe_put_cover_photo(params, nil), do: Map.put(params, "cover_photo_id", nil)
  defp maybe_put_cover_photo(params, photo), do: Map.put(params, "cover_photo_id", photo.id)

  # --- Photo Picker ---

  def handle_event("open_cover_picker", _, socket) do
    {:noreply, assign(socket, show_photo_picker: true, picker_mode: :cover, picker_gallery: nil, picker_photos: [])}
  end

  def handle_event("open_content_picker", _, socket) do
    {:noreply, assign(socket, show_photo_picker: true, picker_mode: :content, picker_gallery: nil, picker_photos: [])}
  end

  def handle_event("close_photo_picker", _, socket) do
    {:noreply, assign(socket, show_photo_picker: false, picker_mode: nil, picker_gallery: nil, picker_photos: [])}
  end

  def handle_event("select_picker_gallery", %{"id" => gallery_id}, socket) do
    gallery = Galleries.get_gallery!(gallery_id)
    photos = Galleries.list_photos(gallery.id) |> Enum.filter(&(&1.status == "processed"))
    {:noreply, assign(socket, picker_gallery: gallery, picker_photos: photos)}
  end

  def handle_event("picker_back_to_galleries", _, socket) do
    {:noreply, assign(socket, picker_gallery: nil, picker_photos: [])}
  end

  def handle_event("select_photo", %{"id" => photo_id}, socket) do
    photo = Enum.find(socket.assigns.picker_photos, &(&1.id == String.to_integer(photo_id)))

    if photo do
      case socket.assigns.picker_mode do
        :cover ->
          {:noreply,
           socket
           |> assign(:cover_photo, photo)
           |> assign(:show_photo_picker, false)}

        :content ->
          url = Ancestry.Uploaders.Photo.url({photo.image, photo}, :large)

          {:noreply,
           socket
           |> push_event("insert_photo", %{url: url, photo_id: photo.id})
           |> assign(:show_photo_picker, false)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_cover_photo", _, socket) do
    {:noreply, assign(socket, :cover_photo, nil)}
  end

  # --- Delete ---

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    {:ok, _} = Memories.delete_memory(socket.assigns.memory)

    {:noreply,
     socket
     |> put_flash(:info, "Memory deleted")
     |> push_navigate(to: vault_path(socket))}
  end

  # --- @Mention search ---

  def handle_event("search_mentions", %{"query" => query}, socket) do
    org_id = socket.assigns.current_scope.organization.id

    results =
      if String.length(query) >= 1 do
        People.search_people(org_id, query)
        |> Enum.take(5)
        |> Enum.map(fn p ->
          %{id: p.id, name: "#{p.given_name} #{p.surname}"}
        end)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:mention_results, results)
     |> push_event("mention_results", %{results: results})}
  end

  defp vault_path(socket) do
    ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}/vaults/#{socket.assigns.vault.id}"
  end
end
```

**Note:** The existing `People.search_people/3` takes `(query, exclude_family_id, org_id)`. Add a 2-arity version to `lib/ancestry/people.ex` for mention search:

```elixir
def search_people(org_id, query) do
  search_people(query, nil, org_id)
end
```

Or if the 3-arity version requires a non-nil `exclude_family_id`, add a new function that does a simple ILIKE on given_name/surname scoped to the organization. Read `lib/ancestry/people.ex` to confirm the existing API.

- [ ] **Step 2: Create the template**

```heex
<%!-- lib/web/live/memory_live/form.html.heex --%>
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <%!-- Header --%>
  <div class="flex items-center gap-3 mb-6">
    <.link
      navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/vaults/#{@vault.id}"}
      class="p-1 rounded text-ds-on-surface-variant hover:text-ds-primary hover:bg-ds-primary/10 transition-colors"
    >
      <.icon name="hero-arrow-left" class="w-5 h-5" />
    </.link>
    <h1 class="text-2xl font-ds-heading font-bold text-ds-on-surface">
      <%= if @live_action == :new, do: "New Memory", else: "Edit Memory" %>
    </h1>
  </div>

  <div class="max-w-3xl">
    <.form for={@form} id="memory-form" phx-submit="save" phx-change="validate" class="space-y-6">
      <%!-- Name --%>
      <.input field={@form[:name]} label="Memory name" placeholder="e.g. Grandma's Birthday" autofocus />

      <%!-- Cover Photo --%>
      <div>
        <label class="block text-sm font-ds-body font-semibold text-ds-on-surface mb-2">Cover photo (optional)</label>
        <%= if @cover_photo do %>
          <div class="relative inline-block">
            <img
              src={Ancestry.Uploaders.Photo.url({@cover_photo.image, @cover_photo}, :thumbnail)}
              class="w-32 h-24 object-cover rounded-ds-sharp"
            />
            <button
              type="button"
              phx-click="remove_cover_photo"
              class="absolute -top-2 -right-2 bg-ds-error text-white rounded-full p-0.5"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
        <% else %>
          <button
            type="button"
            phx-click="open_cover_picker"
            class="bg-ds-surface-high text-ds-on-surface rounded-ds-sharp px-4 py-2 text-sm font-ds-body hover:bg-ds-surface-highest transition-colors"
          >
            Choose from album
          </button>
        <% end %>
      </div>

      <%!-- Trix Editor --%>
      <div>
        <label class="block text-sm font-ds-body font-semibold text-ds-on-surface mb-2">Content</label>
        <div id="trix-wrapper" phx-hook="TrixEditor" phx-update="ignore">
          <input type="hidden" name={@form[:content].name} id="memory-content-input" value={@form[:content].value || ""} />
          <div class="mb-2">
            <button
              type="button"
              class="trix-custom-btn bg-ds-surface-high text-ds-on-surface rounded-ds-sharp px-3 py-1 text-sm hover:bg-ds-surface-highest transition-colors"
              data-action="insert-photo"
            >
              <.icon name="hero-photo" class="w-4 h-4 inline" /> Insert Photo
            </button>
          </div>
          <trix-editor input="memory-content-input" class="trix-content min-h-[200px] bg-ds-surface-card rounded-ds-sharp border border-ds-outline-variant p-4"></trix-editor>
        </div>
      </div>

      <%!-- Actions --%>
      <div class="flex gap-3">
        <button
          type="submit"
          class="bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp px-6 py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
        >
          <%= if @live_action == :new, do: "Create Memory", else: "Save Changes" %>
        </button>
        <.link
          navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/vaults/#{@vault.id}"}
          class="bg-ds-surface-high text-ds-on-surface rounded-ds-sharp px-6 py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
        >
          Cancel
        </.link>
        <%= if @live_action == :edit do %>
          <button
            type="button"
            phx-click="request_delete"
            class="ml-auto text-ds-error text-sm font-ds-body font-semibold hover:underline"
          >
            Delete
          </button>
        <% end %>
      </div>
    </.form>
  </div>

  <%!-- Photo Picker Modal --%>
  <%= if @show_photo_picker do %>
    <div
      class="fixed inset-0 z-50 flex items-end lg:items-center justify-center"
      phx-window-keydown="close_photo_picker"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="close_photo_picker" />
      <div
        id="photo-picker-modal"
        class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full h-full lg:h-auto max-w-none lg:max-w-2xl mx-0 lg:mx-4 rounded-none lg:rounded-ds-sharp p-6 overflow-y-auto"
        role="dialog"
        aria-modal="true"
      >
        <%= if @picker_gallery == nil do %>
          <%!-- Step 1: Album list --%>
          <h2 class="text-xl font-ds-heading font-bold text-ds-on-surface mb-4">Choose an album</h2>
          <div class="grid grid-cols-2 gap-3">
            <button
              :for={gallery <- @galleries}
              type="button"
              phx-click="select_picker_gallery"
              phx-value-id={gallery.id}
              class="bg-ds-surface-low rounded-ds-sharp p-4 text-left hover:bg-ds-surface-high transition-colors"
            >
              <span class="font-ds-body font-semibold text-ds-on-surface">{gallery.name}</span>
            </button>
          </div>
          <%= if @galleries == [] do %>
            <p class="text-ds-on-surface-variant text-sm">No albums in this family.</p>
          <% end %>
        <% else %>
          <%!-- Step 2: Photo grid --%>
          <div class="flex items-center gap-2 mb-4">
            <button type="button" phx-click="picker_back_to_galleries" class="p-1 rounded hover:bg-ds-surface-high">
              <.icon name="hero-arrow-left" class="w-5 h-5 text-ds-on-surface-variant" />
            </button>
            <h2 class="text-xl font-ds-heading font-bold text-ds-on-surface">{@picker_gallery.name}</h2>
          </div>
          <div class="grid grid-cols-3 lg:grid-cols-4 gap-2">
            <button
              :for={photo <- @picker_photos}
              type="button"
              phx-click="select_photo"
              phx-value-id={photo.id}
              class="aspect-square overflow-hidden rounded-ds-sharp hover:ring-2 hover:ring-ds-primary transition-all"
            >
              <img
                src={Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)}
                class="w-full h-full object-cover"
              />
            </button>
          </div>
          <%= if @picker_photos == [] do %>
            <p class="text-ds-on-surface-variant text-sm">No processed photos in this album.</p>
          <% end %>
        <% end %>
        <button
          type="button"
          phx-click="close_photo_picker"
          class="absolute top-4 right-4 p-1 rounded text-ds-on-surface-variant hover:bg-ds-surface-high"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>
      </div>
    </div>
  <% end %>

  <%!-- Delete Confirmation Modal --%>
  <%= if @confirm_delete do %>
    <div
      class="fixed inset-0 z-50 flex items-end lg:items-center justify-center"
      phx-window-keydown="cancel_delete"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_delete" />
      <div
        class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp p-8"
        role="dialog"
        aria-modal="true"
        phx-mounted={JS.focus_first()}
      >
        <h2 class="text-xl font-ds-heading font-bold text-ds-on-surface mb-2">Delete Memory</h2>
        <p class="text-ds-on-surface-variant mb-6 font-ds-body">
          Delete <span class="font-semibold">"{@memory && @memory.name}"</span>? This cannot be undone.
        </p>
        <div class="flex gap-3">
          <button
            phx-click="confirm_delete"
            class="flex-1 bg-ds-error text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:opacity-90 transition-opacity"
          >
            Delete
          </button>
          <button
            phx-click="cancel_delete"
            class="flex-1 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  <% end %>
</Layouts.app>
```

- [ ] **Step 3: Verify compilation and basic page load**

```bash
mix compile --warnings-as-errors
```

Start the dev server. Navigate to the new memory form via the vault page. Verify the page renders with the Trix editor.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/memory_live/form.ex lib/web/live/memory_live/form.html.heex
git commit -m "feat: add MemoryLive.Form with Trix editor and photo picker"
```

---

## Task 14: @Mention Support in TrixEditor Hook

**Files:**
- Modify: `assets/js/trix_editor.js`

- [ ] **Step 1: Add @mention detection and dropdown to the TrixEditor hook**

Update `assets/js/trix_editor.js`:

```javascript
import "trix"

const TrixEditor = {
  mounted() {
    const editorEl = this.el.querySelector("trix-editor")
    if (!editorEl) return

    this.editorEl = editorEl
    this.mentionQuery = null
    this.mentionDropdown = null

    // Block file uploads
    this.el.addEventListener("trix-file-accept", (e) => {
      e.preventDefault()
    })

    // Sync content to hidden input
    this.el.addEventListener("trix-change", () => {
      const input = this.el.querySelector("input[type=hidden]")
      if (input) {
        const doc = editorEl.editor.getDocument().toString()
        input.value = doc !== "\n" ? editorEl.innerHTML : ""
        input.dispatchEvent(new Event("input", { bubbles: true }))
      }
    })

    // Detect @ for mentions
    this.el.addEventListener("trix-change", () => {
      this._checkForMention()
    })

    // Handle keyboard in mention dropdown
    this.el.addEventListener("keydown", (e) => {
      if (this.mentionDropdown) {
        if (e.key === "ArrowDown" || e.key === "ArrowUp") {
          e.preventDefault()
          this._navigateDropdown(e.key === "ArrowDown" ? 1 : -1)
        } else if (e.key === "Enter" && this._getSelectedItem()) {
          e.preventDefault()
          this._selectMention(this._getSelectedItem())
        } else if (e.key === "Escape") {
          e.preventDefault()
          this._closeMentionDropdown()
        }
      }
    })

    // Handle Insert Photo button
    const insertBtn = this.el.querySelector("[data-action='insert-photo']")
    if (insertBtn) {
      insertBtn.addEventListener("click", (e) => {
        e.preventDefault()
        this.pushEvent("open_content_picker", {})
      })
    }

    // Receive photo insertion from LiveView
    this.handleEvent("insert_photo", ({ url, photo_id }) => {
      const attachment = new Trix.Attachment({
        contentType: "application/vnd.memory-photo",
        content: `<img data-photo-id="${photo_id}" src="${url}" class="max-w-full rounded" />`,
      })
      editorEl.editor.insertAttachment(attachment)
    })

    // Receive mention search results from LiveView
    this.handleEvent("mention_results", ({ results }) => {
      this._showMentionDropdown(results)
    })
  },

  destroyed() {
    this._closeMentionDropdown()
  },

  _checkForMention() {
    const editor = this.editorEl.editor
    const position = editor.getPosition()
    const text = editor.getDocument().toString().slice(0, position)

    // Find the last @ that isn't preceded by a word char
    const match = text.match(/(?:^|[^a-zA-Z0-9])@([a-zA-Z0-9 ]{0,30})$/)

    if (match) {
      const query = match[1]
      if (query.length >= 1) {
        this.mentionQuery = query
        this.mentionStart = position - query.length - 1
        this.pushEvent("search_mentions", { query })
      }
    } else {
      this._closeMentionDropdown()
    }
  },

  _showMentionDropdown(results) {
    this._closeMentionDropdown()
    if (results.length === 0) return

    const dropdown = document.createElement("div")
    dropdown.className = "absolute z-50 bg-ds-surface-card shadow-lg rounded-ds-sharp border border-ds-outline-variant py-1 max-h-48 overflow-y-auto"
    dropdown.style.minWidth = "200px"

    results.forEach((person, index) => {
      const item = document.createElement("button")
      item.type = "button"
      item.className = `w-full text-left px-3 py-2 text-sm hover:bg-ds-surface-high transition-colors ${index === 0 ? "bg-ds-surface-low" : ""}`
      item.dataset.personId = person.id
      item.dataset.personName = person.name
      item.dataset.index = index
      item.textContent = person.name
      item.addEventListener("click", () => this._selectMention(item))
      dropdown.appendChild(item)
    })

    // Position near the editor cursor
    const editorRect = this.editorEl.getBoundingClientRect()
    dropdown.style.position = "absolute"
    dropdown.style.top = `${editorRect.bottom + 4}px`
    dropdown.style.left = `${editorRect.left}px`

    document.body.appendChild(dropdown)
    this.mentionDropdown = dropdown
    this.selectedIndex = 0
  },

  _closeMentionDropdown() {
    if (this.mentionDropdown) {
      this.mentionDropdown.remove()
      this.mentionDropdown = null
      this.mentionQuery = null
      this.selectedIndex = 0
    }
  },

  _navigateDropdown(direction) {
    if (!this.mentionDropdown) return
    const items = this.mentionDropdown.querySelectorAll("button")
    items[this.selectedIndex]?.classList.remove("bg-ds-surface-low")
    this.selectedIndex = Math.max(0, Math.min(items.length - 1, this.selectedIndex + direction))
    items[this.selectedIndex]?.classList.add("bg-ds-surface-low")
  },

  _getSelectedItem() {
    if (!this.mentionDropdown) return null
    return this.mentionDropdown.querySelectorAll("button")[this.selectedIndex]
  },

  _selectMention(item) {
    const personId = item.dataset.personId
    const personName = item.dataset.personName
    const editor = this.editorEl.editor

    // Delete the @query text
    const position = editor.getPosition()
    const deleteCount = (this.mentionQuery?.length || 0) + 1 // +1 for @
    editor.setSelectedRange([position - deleteCount, position])
    editor.deleteInDirection("backward")

    // Insert mention as attachment
    const attachment = new Trix.Attachment({
      contentType: "application/vnd.memory-mention",
      content: `<span data-person-id="${personId}">@${personName}</span>`,
    })
    editor.insertAttachment(attachment)

    this._closeMentionDropdown()
  }
}

export { TrixEditor }
```

- [ ] **Step 2: Verify the build**

```bash
cd assets && npx esbuild js/app.js --bundle --outdir=../priv/static/assets 2>&1 | head -5 && cd ..
```

- [ ] **Step 3: Manual test**

Start the dev server. Create a vault and a memory. Type `@` followed by a person's name. Verify the dropdown appears and selecting a person inserts a mention.

- [ ] **Step 4: Commit**

```bash
git add assets/js/trix_editor.js
git commit -m "feat: add @mention support to TrixEditor hook"
```

---

## Task 15: Trix CSS Customization

**Files:**
- Modify: `assets/css/app.css`

- [ ] **Step 1: Add Trix and hover card styles**

Add to `assets/css/app.css`:

```css
/* === Trix Editor Customization === */
trix-editor {
  min-height: 200px;
}

trix-editor .attachment--content {
  display: inline;
}

/* Person hover card - desktop only */
.memory-mention-wrapper {
  position: relative;
  display: inline-block;
}

.memory-mention-card {
  display: none;
  position: absolute;
  bottom: 100%;
  left: 50%;
  transform: translateX(-50%);
  margin-bottom: 4px;
  z-index: 50;
  pointer-events: none;
}

@media (hover: hover) {
  .memory-mention-wrapper:hover .memory-mention-card {
    display: block;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add assets/css/app.css
git commit -m "feat: add Trix and hover card CSS customizations"
```

---

## Task 16: User Flow Tests

**Files:**
- Create: `test/user_flows/memory_vault_crud_test.exs`

Read `test/user_flows/CLAUDE.md` for the exact conventions before writing these tests.

- [ ] **Step 1: Write the user flow test**

```elixir
# test/user_flows/memory_vault_crud_test.exs
defmodule Web.UserFlows.MemoryVaultCrudTest do
  use Web.E2ECase

  setup do
    org = insert(:organization)
    family = insert(:family, organization: org, name: "Test Family")
    gallery = insert(:gallery, family: family, name: "Summer Photos")
    photo = insert(:photo, gallery: gallery, status: "processed")

    person =
      insert(:person,
        given_name: "Alice",
        surname: "Smith",
        organization: org
      )

    Ancestry.People.add_to_family(person, family)

    %{org: org, family: family, gallery: gallery, photo: photo, person: person}
  end

  # Given a family with no vaults
  # When the user visits the family page
  # And clicks the + button next to Memory Vaults
  # And fills in the vault name
  # And clicks Create
  # Then a new vault appears in the vault list
  test "create a vault from family show page", %{conn: conn, org: org, family: family} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    # Verify empty state
    conn = conn |> assert_has("text", text: "No memory vaults yet.")

    # Open the create modal
    conn =
      conn
      |> click("button[phx-click='open_new_vault_modal']")
      |> assert_has("#new-vault-modal")

    # Fill in the name and submit
    conn =
      conn
      |> fill_in("#new-vault-form input[name='vault[name]']", with: "Summer Memories")
      |> click("#new-vault-form button[type='submit']")
      |> wait_liveview()

    # Vault should appear
    conn |> assert_has("text", text: "Summer Memories")
  end

  # Given a vault with memories
  # When the user visits the vault page
  # Then they see the memory cards
  # When they click delete vault
  # And confirm
  # Then they are redirected to the family page
  test "delete a vault", %{conn: conn, org: org, family: family} do
    conn = log_in_e2e(conn)

    vault = insert(:vault, family: family, name: "To Delete")

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/vaults/#{vault.id}")
      |> wait_liveview()

    conn =
      conn
      |> click("button[phx-click='request_delete_vault']")
      |> assert_has("#confirm-delete-vault-modal")
      |> click("button[phx-click='confirm_delete_vault']")
      |> wait_liveview()

    # Should be back on family page
    conn |> assert_has("text", text: "Vault deleted")
  end
end
```

**Note:** The exact selector patterns and E2E helper functions depend on what `Web.E2ECase` provides. The implementer should read `test/user_flows/CLAUDE.md` and adapt selectors accordingly. These tests may need adjustments based on the actual DOM structure.

- [ ] **Step 2: Run the user flow tests**

```bash
mix test test/user_flows/memory_vault_crud_test.exs
```

Expected: tests should PASS if the dev server is available and the E2E setup is correct.

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/memory_vault_crud_test.exs
git commit -m "test: add user flow tests for memory vault CRUD"
```

---

## Task 17: Run Precommit

**Files:** None (verification only)

- [ ] **Step 1: Run the precommit alias**

```bash
mix precommit
```

Expected: compilation (warnings-as-errors), formatting, and tests all pass.

- [ ] **Step 2: Fix any issues**

If precommit finds issues (formatting, warnings, test failures), fix them and re-run.

- [ ] **Step 3: Final commit if fixes were needed**

```bash
git add -A
git commit -m "fix: resolve precommit issues"
```

---

## Summary

| Task | Description | Dependencies |
|------|-------------|-------------|
| 1 | Database migrations | None |
| 2 | Schemas (Vault, Memory, MemoryMention) | 1 |
| 3 | Factories | 2 |
| 4 | Context — Vault CRUD | 2, 3 |
| 5 | ContentParser | 2 |
| 6 | Context — Memory CRUD with Multi | 4, 5 |
| 7 | PubSub broadcasts | 6 |
| 8 | ContentRenderer + sanitization | 5 |
| 9 | Routes | 2 |
| 10 | VaultLive.Show | 6, 7, 9 |
| 11 | FamilyLive.Show vault section + modal | 4, 9 |
| 12 | Install Trix + JS hook setup | None |
| 13 | MemoryLive.Form (New/Edit) | 6, 9, 12 |
| 14 | @Mention support in hook | 13 |
| 15 | Trix CSS customization | 12 |
| 16 | User flow tests | 10, 11, 13 |
| 17 | Run precommit | All |
