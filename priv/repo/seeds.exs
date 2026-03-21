# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Ancestry.Repo.insert!(%Ancestry.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Ancestry.People
alias Ancestry.Families
alias Ancestry.Relationships

# ---------------------------------------------------------------------------
# Family
# ---------------------------------------------------------------------------

{:ok, family} = Families.create_family(%{name: "The Thompsons"})

# ---------------------------------------------------------------------------
# Helper — create a person in the family
# ---------------------------------------------------------------------------

person = fn attrs ->
  {:ok, p} = People.create_person(family, attrs)
  p
end

# ---------------------------------------------------------------------------
# Generation 1 — Great-grandparents
# ---------------------------------------------------------------------------

harold =
  person.(%{
    given_name: "Harold",
    surname: "Thompson",
    gender: "male",
    birth_year: 1920,
    birth_month: 3,
    birth_day: 14,
    death_year: 1995,
    death_month: 11,
    death_day: 2,
    deceased: true
  })

margaret =
  person.(%{
    given_name: "Margaret",
    surname: "Thompson",
    surname_at_birth: "Ellis",
    gender: "female",
    birth_year: 1922,
    birth_month: 7,
    birth_day: 8,
    death_year: 2001,
    death_month: 4,
    death_day: 19,
    deceased: true
  })

{:ok, _} =
  Relationships.create_relationship(harold, margaret, "married", %{
    marriage_year: 1942,
    marriage_month: 6,
    marriage_day: 15
  })

# ---------------------------------------------------------------------------
# Generation 2 — Grandparents
# ---------------------------------------------------------------------------

robert =
  person.(%{
    given_name: "Robert",
    surname: "Thompson",
    gender: "male",
    birth_year: 1943,
    birth_month: 4,
    birth_day: 22
  })

patricia =
  person.(%{
    given_name: "Patricia",
    surname: "Thompson",
    surname_at_birth: "Walsh",
    gender: "female",
    birth_year: 1945,
    birth_month: 9,
    birth_day: 3
  })

dorothy =
  person.(%{
    given_name: "Dorothy",
    surname: "Thompson",
    gender: "female",
    birth_year: 1946,
    birth_month: 12,
    birth_day: 1
  })

george =
  person.(%{
    given_name: "George",
    surname: "Campbell",
    gender: "male",
    birth_year: 1944,
    birth_month: 2,
    birth_day: 17,
    death_year: 2010,
    death_month: 8,
    death_day: 5,
    deceased: true
  })

frank =
  person.(%{
    given_name: "Frank",
    surname: "Morris",
    gender: "male",
    birth_year: 1948,
    birth_month: 5,
    birth_day: 30
  })

william =
  person.(%{
    given_name: "William",
    surname: "Thompson",
    gender: "male",
    birth_year: 1950,
    birth_month: 8,
    birth_day: 11
  })

linda =
  person.(%{
    given_name: "Linda",
    surname: "Baker",
    gender: "female",
    birth_year: 1952,
    birth_month: 1,
    birth_day: 25
  })

sandra =
  person.(%{
    given_name: "Sandra",
    surname: "Thompson",
    surname_at_birth: "Mitchell",
    gender: "female",
    birth_year: 1955,
    birth_month: 10,
    birth_day: 14
  })

# -- Gen 2 parent relationships (Harold & Margaret are parents of all three) --

for child <- [robert, dorothy, william] do
  {:ok, _} = Relationships.create_relationship(harold, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(margaret, child, "parent", %{role: "mother"})
end

# -- Gen 2 partner relationships --

# Robert & Patricia — married
{:ok, _} =
  Relationships.create_relationship(robert, patricia, "married", %{
    marriage_year: 1965,
    marriage_month: 5,
    marriage_day: 22
  })

# Dorothy & George — married, George deceased (widowed & remarried scenario)
{:ok, _} =
  Relationships.create_relationship(dorothy, george, "married", %{
    marriage_year: 1968,
    marriage_month: 9,
    marriage_day: 7
  })

# Dorothy & Frank — second marriage (childless couple)
{:ok, _} =
  Relationships.create_relationship(dorothy, frank, "married", %{
    marriage_year: 2012,
    marriage_month: 3,
    marriage_day: 20
  })

# William & Linda — divorced
{:ok, _} =
  Relationships.create_relationship(william, linda, "divorced", %{
    marriage_year: 1972,
    marriage_month: 4,
    marriage_day: 10,
    divorce_year: 1978,
    divorce_month: 9
  })

# William & Sandra — current marriage
{:ok, _} =
  Relationships.create_relationship(william, sandra, "married", %{
    marriage_year: 1980,
    marriage_month: 7,
    marriage_day: 5
  })

# ---------------------------------------------------------------------------
# Generation 3 — Parents
# ---------------------------------------------------------------------------

james =
  person.(%{
    given_name: "James",
    surname: "Thompson",
    gender: "male",
    birth_year: 1966,
    birth_month: 2,
    birth_day: 14
  })

susan =
  person.(%{
    given_name: "Susan",
    surname: "Thompson",
    gender: "female",
    birth_year: 1969,
    birth_month: 6,
    birth_day: 28
  })

catherine =
  person.(%{
    given_name: "Catherine",
    surname: "Thompson",
    surname_at_birth: "Harris",
    gender: "female",
    birth_year: 1968,
    birth_month: 11,
    birth_day: 9
  })

karen =
  person.(%{
    given_name: "Karen",
    surname: "Campbell",
    gender: "female",
    birth_year: 1970,
    birth_month: 3,
    birth_day: 16
  })

david =
  person.(%{
    given_name: "David",
    surname: "Clarke",
    gender: "male",
    birth_year: 1969,
    birth_month: 7,
    birth_day: 4
  })

michael =
  person.(%{
    given_name: "Michael",
    surname: "Thompson",
    gender: "male",
    birth_year: 1974,
    birth_month: 10,
    birth_day: 21
  })

rachel =
  person.(%{
    given_name: "Rachel",
    surname: "Thompson",
    surname_at_birth: "Green",
    gender: "female",
    birth_year: 1976,
    birth_month: 5,
    birth_day: 12
  })

andrew =
  person.(%{
    given_name: "Andrew",
    surname: "Thompson",
    gender: "male",
    birth_year: 1982,
    birth_month: 1,
    birth_day: 7
  })

jessica =
  person.(%{
    given_name: "Jessica",
    surname: "Thompson",
    surname_at_birth: "Taylor",
    gender: "female",
    birth_year: 1984,
    birth_month: 8,
    birth_day: 19
  })

emily =
  person.(%{
    given_name: "Emily",
    surname: "Thompson",
    gender: "female",
    birth_year: 1985,
    birth_month: 12,
    birth_day: 3
  })

daniel =
  person.(%{
    given_name: "Daniel",
    surname: "Thompson",
    gender: "male",
    birth_year: 1979,
    birth_month: 6,
    birth_day: 15
  })

# -- Gen 3 parent relationships --

# Robert & Patricia → James, Susan
for child <- [james, susan] do
  {:ok, _} = Relationships.create_relationship(robert, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(patricia, child, "parent", %{role: "mother"})
end

# Dorothy & George → Karen
{:ok, _} = Relationships.create_relationship(george, karen, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(dorothy, karen, "parent", %{role: "mother"})

# William & Linda → Michael (child of divorced couple)
{:ok, _} = Relationships.create_relationship(william, michael, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(linda, michael, "parent", %{role: "mother"})

# William & Sandra → Andrew, Emily (half-siblings of Michael)
for child <- [andrew, emily] do
  {:ok, _} = Relationships.create_relationship(william, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(sandra, child, "parent", %{role: "mother"})
end

# William → Daniel (solo child, no co-parent)
{:ok, _} = Relationships.create_relationship(william, daniel, "parent", %{role: "father"})

# -- Gen 3 partner relationships --

# James & Catherine
{:ok, _} =
  Relationships.create_relationship(james, catherine, "married", %{
    marriage_year: 1990,
    marriage_month: 8,
    marriage_day: 18
  })

# Karen & David
{:ok, _} =
  Relationships.create_relationship(karen, david, "married", %{
    marriage_year: 1993,
    marriage_month: 6,
    marriage_day: 12
  })

# Michael & Rachel
{:ok, _} =
  Relationships.create_relationship(michael, rachel, "married", %{
    marriage_year: 1998,
    marriage_month: 10,
    marriage_day: 3
  })

# Andrew & Jessica
{:ok, _} =
  Relationships.create_relationship(andrew, jessica, "married", %{
    marriage_year: 2008,
    marriage_month: 5,
    marriage_day: 24
  })

# Susan — single, no partner
# Emily — single, no partner
# Daniel — single, no partner

# ---------------------------------------------------------------------------
# Generation 4 — Children (youngest generation)
# ---------------------------------------------------------------------------

oliver =
  person.(%{
    given_name: "Oliver",
    surname: "Thompson",
    gender: "male",
    birth_year: 1992,
    birth_month: 4,
    birth_day: 10
  })

charlotte =
  person.(%{
    given_name: "Charlotte",
    surname: "Thompson",
    gender: "female",
    birth_year: 1994,
    birth_month: 7,
    birth_day: 25
  })

thomas =
  person.(%{
    given_name: "Thomas",
    surname: "Thompson",
    gender: "male",
    birth_year: 1997,
    birth_month: 11,
    birth_day: 1
  })

sophie =
  person.(%{
    given_name: "Sophie",
    surname: "Clarke",
    gender: "female",
    birth_year: 1995,
    birth_month: 3,
    birth_day: 8
  })

benjamin =
  person.(%{
    given_name: "Benjamin",
    surname: "Clarke",
    gender: "male",
    birth_year: 1998,
    birth_month: 9,
    birth_day: 14
  })

lily =
  person.(%{
    given_name: "Lily",
    surname: "Thompson",
    gender: "female",
    birth_year: 2001,
    birth_month: 2,
    birth_day: 20
  })

noah =
  person.(%{
    given_name: "Noah",
    surname: "Thompson",
    gender: "male",
    birth_year: 2010,
    birth_month: 6,
    birth_day: 5
  })

emma =
  person.(%{
    given_name: "Emma",
    surname: "Thompson",
    gender: "female",
    birth_year: 2012,
    birth_month: 12,
    birth_day: 17
  })

max =
  person.(%{
    given_name: "Max",
    surname: "Thompson",
    gender: "male",
    birth_year: 2015,
    birth_month: 4,
    birth_day: 29
  })

# -- Gen 4 parent relationships --

# James & Catherine → Oliver, Charlotte, Thomas
for child <- [oliver, charlotte, thomas] do
  {:ok, _} = Relationships.create_relationship(james, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(catherine, child, "parent", %{role: "mother"})
end

# Karen & David → Sophie, Benjamin
for child <- [sophie, benjamin] do
  {:ok, _} = Relationships.create_relationship(david, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(karen, child, "parent", %{role: "mother"})
end

# Michael & Rachel → Lily
{:ok, _} = Relationships.create_relationship(michael, lily, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(rachel, lily, "parent", %{role: "mother"})

# Andrew & Jessica → Noah, Emma
for child <- [noah, emma] do
  {:ok, _} = Relationships.create_relationship(andrew, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(jessica, child, "parent", %{role: "mother"})
end

# Emily → Max (solo child, no co-parent)
{:ok, _} = Relationships.create_relationship(emily, max, "parent", %{role: "mother"})

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
# 30 people across 4 generations
# Configurations tested:
#   - Standard married couples (Harold & Margaret, Robert & Patricia, James & Catherine, etc.)
#   - Widowed & remarried (Dorothy: George deceased, then married Frank)
#   - Divorced & remarried (William: ex-wife Linda, then married Sandra)
#   - Childless couple (Dorothy & Frank)
#   - Solo children — no co-parent (William → Daniel, Emily → Max)
#   - Half-siblings (Michael vs Andrew/Emily share father William, different mothers)
#   - Single people with no partner or children (Susan, Daniel)
#   - Varying family sizes (1, 2, and 3 children)

# Set Harold as the default person (focus of the family tree)
People.set_default_member(family.id, harold.id)

IO.puts("Seeded The Thompsons: 30 people, 4 generations")
