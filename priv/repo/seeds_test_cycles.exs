# Seed script for test families demonstrating cycle types and edge cases.
#
# Run with: mix run priv/repo/seeds_test_cycles.exs
#
# Creates an organization "Cycle Test Org" with three families:
#   1. "Intermarried Clans"  — all 5 cycle types from the CLAUDE.md catalog
#   2. "Blended Saga"        — ex-partners, late partners, solo children
#   3. "The Prolific Elders" — grandparents with 13 children

import Ecto.Query

alias Ancestry.Organizations
alias Ancestry.Organizations.AccountOrganization
alias Ancestry.People
alias Ancestry.Families
alias Ancestry.Relationships

# ---------------------------------------------------------------------------
# Organization
# ---------------------------------------------------------------------------

{:ok, org} = Organizations.create_organization(%{name: "Cycle Test Org"})

for account <- Ancestry.Repo.all(Ancestry.Identity.Account) do
  unless Ancestry.Repo.get_by(AccountOrganization,
           account_id: account.id,
           organization_id: org.id
         ) do
    Ancestry.Repo.insert!(%AccountOrganization{
      account_id: account.id,
      organization_id: org.id
    })
  end
end

# ###########################################################################
#
#  FAMILY 1 — "Intermarried Clans"
#
#  Demonstrates all 5 cycle types documented in lib/ancestry/people/CLAUDE.md.
#  The focus person for testing is Zara Ashford (the youngest).
#
# ###########################################################################

{:ok, f1} = Families.create_family(org, %{name: "Intermarried Clans"})

p1 = fn attrs ->
  {:ok, p} = People.create_person(f1, attrs)
  p
end

# ---- Shared ancestors (the grandparents for Types 1, 4, 5) ----

edgar =
  p1.(%{
    given_name: "Edgar",
    surname: "Ashford",
    gender: "male",
    birth_year: 1920,
    deceased: true,
    death_year: 1990
  })

nora =
  p1.(%{
    given_name: "Nora",
    surname: "Ashford",
    surname_at_birth: "Blackwell",
    gender: "female",
    birth_year: 1922,
    deceased: true,
    death_year: 1998
  })

{:ok, _} = Relationships.create_relationship(edgar, nora, "married", %{marriage_year: 1940})

# ---- Edgar & Nora's children (4 sons) ----

clifford = p1.(%{given_name: "Clifford", surname: "Ashford", gender: "male", birth_year: 1941})
desmond = p1.(%{given_name: "Desmond", surname: "Ashford", gender: "male", birth_year: 1943})
gilbert = p1.(%{given_name: "Gilbert", surname: "Ashford", gender: "male", birth_year: 1945})
humphrey = p1.(%{given_name: "Humphrey", surname: "Ashford", gender: "male", birth_year: 1948})

for child <- [clifford, desmond, gilbert, humphrey] do
  {:ok, _} = Relationships.create_relationship(edgar, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(nora, child, "parent", %{role: "mother"})
end

# ---- Second grandparent couple (Whitfield family, for Types 1, 3, 5) ----

rupert =
  p1.(%{
    given_name: "Rupert",
    surname: "Whitfield",
    gender: "male",
    birth_year: 1918,
    deceased: true,
    death_year: 1985
  })

opal =
  p1.(%{
    given_name: "Opal",
    surname: "Whitfield",
    surname_at_birth: "Crenshaw",
    gender: "female",
    birth_year: 1921,
    deceased: true,
    death_year: 1999
  })

{:ok, _} = Relationships.create_relationship(rupert, opal, "married", %{marriage_year: 1939})

# ---- Rupert & Opal's children (3 daughters) ----

ivy = p1.(%{given_name: "Ivy", surname: "Whitfield", gender: "female", birth_year: 1940})
mabel = p1.(%{given_name: "Mabel", surname: "Whitfield", gender: "female", birth_year: 1942})
greta = p1.(%{given_name: "Greta", surname: "Whitfield", gender: "female", birth_year: 1946})

for child <- [ivy, mabel, greta] do
  {:ok, _} = Relationships.create_relationship(rupert, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(opal, child, "parent", %{role: "mother"})
end

# ====================================================================
# TYPE 1 — Cousins who marry (pedigree collapse)
#
# Clifford marries Ivy. Desmond marries Mabel. Their children (cousins)
# marry each other → shared grandparents Edgar+Nora and Rupert+Opal.
# ====================================================================

{:ok, _} = Relationships.create_relationship(clifford, ivy, "married", %{marriage_year: 1962})
{:ok, _} = Relationships.create_relationship(desmond, mabel, "married", %{marriage_year: 1964})

# Children of Clifford + Ivy
leon = p1.(%{given_name: "Leon", surname: "Ashford", gender: "male", birth_year: 1965})
{:ok, _} = Relationships.create_relationship(clifford, leon, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(ivy, leon, "parent", %{role: "mother"})

# Children of Desmond + Mabel
sylvia = p1.(%{given_name: "Sylvia", surname: "Ashford", gender: "female", birth_year: 1967})
{:ok, _} = Relationships.create_relationship(desmond, sylvia, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(mabel, sylvia, "parent", %{role: "mother"})

# Leon and Sylvia are first cousins — they marry
{:ok, _} = Relationships.create_relationship(leon, sylvia, "married", %{marriage_year: 1990})

# Their child is the pedigree-collapse focus
zara = p1.(%{given_name: "Zara", surname: "Ashford", gender: "female", birth_year: 1992})
{:ok, _} = Relationships.create_relationship(leon, zara, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(sylvia, zara, "parent", %{role: "mother"})

# ====================================================================
# TYPE 2 — Woman marries two brothers
#
# Greta first marries Gilbert. Gilbert dies. Greta then marries Humphrey.
# ====================================================================

{:ok, _} =
  Relationships.create_relationship(gilbert, greta, "divorced", %{
    marriage_year: 1966,
    divorce_year: 1975
  })

# Child from Gilbert + Greta
wendell = p1.(%{given_name: "Wendell", surname: "Ashford", gender: "male", birth_year: 1968})
{:ok, _} = Relationships.create_relationship(gilbert, wendell, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(greta, wendell, "parent", %{role: "mother"})

# Greta remarries Humphrey
{:ok, _} = Relationships.create_relationship(humphrey, greta, "married", %{marriage_year: 1976})

# Child from Humphrey + Greta (half-sibling of Wendell)
phoebe = p1.(%{given_name: "Phoebe", surname: "Ashford", gender: "female", birth_year: 1978})
{:ok, _} = Relationships.create_relationship(humphrey, phoebe, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(greta, phoebe, "parent", %{role: "mother"})

# ====================================================================
# TYPE 3 — Two brothers marry two sisters (double first cousins)
# Uses a separate third-party family: the Thorntons.
# ====================================================================

basil =
  p1.(%{
    given_name: "Basil",
    surname: "Thornton",
    gender: "male",
    birth_year: 1915,
    deceased: true,
    death_year: 1980
  })

winifred =
  p1.(%{
    given_name: "Winifred",
    surname: "Thornton",
    surname_at_birth: "Platt",
    gender: "female",
    birth_year: 1918,
    deceased: true,
    death_year: 1992
  })

{:ok, _} = Relationships.create_relationship(basil, winifred, "married", %{marriage_year: 1936})

tilda = p1.(%{given_name: "Tilda", surname: "Thornton", gender: "female", birth_year: 1937})
lorraine = p1.(%{given_name: "Lorraine", surname: "Thornton", gender: "female", birth_year: 1939})

for child <- [tilda, lorraine] do
  {:ok, _} = Relationships.create_relationship(basil, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(winifred, child, "parent", %{role: "mother"})
end

# Clifford also marries Tilda? No — we already married Clifford to Ivy.
# Use fresh Ashford sons for this example: create two new "Ashford-Thornton" men.
# Actually, let's use a separate pair from the Ashford family who are NOT the same
# as Types 1/2. We'll create two more children of Edgar & Nora for this example:
# But that would be 6 total sons. Simpler: use a new unrelated family pair.

floyd =
  p1.(%{
    given_name: "Floyd",
    surname: "Pemberton",
    gender: "male",
    birth_year: 1916,
    deceased: true,
    death_year: 1988
  })

agnes =
  p1.(%{
    given_name: "Agnes",
    surname: "Pemberton",
    surname_at_birth: "Dunn",
    gender: "female",
    birth_year: 1919,
    deceased: true,
    death_year: 1995
  })

{:ok, _} = Relationships.create_relationship(floyd, agnes, "married", %{marriage_year: 1935})

cedric = p1.(%{given_name: "Cedric", surname: "Pemberton", gender: "male", birth_year: 1936})
oswald = p1.(%{given_name: "Oswald", surname: "Pemberton", gender: "male", birth_year: 1938})

for child <- [cedric, oswald] do
  {:ok, _} = Relationships.create_relationship(floyd, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(agnes, child, "parent", %{role: "mother"})
end

# Cedric (Pemberton) marries Tilda (Thornton)
{:ok, _} = Relationships.create_relationship(cedric, tilda, "married", %{marriage_year: 1958})
# Oswald (Pemberton) marries Lorraine (Thornton)
{:ok, _} = Relationships.create_relationship(oswald, lorraine, "married", %{marriage_year: 1960})

# Children — double first cousins
archibald =
  p1.(%{given_name: "Archibald", surname: "Pemberton", gender: "male", birth_year: 1960})

{:ok, _} = Relationships.create_relationship(cedric, archibald, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(tilda, archibald, "parent", %{role: "mother"})

rowena = p1.(%{given_name: "Rowena", surname: "Pemberton", gender: "female", birth_year: 1962})
{:ok, _} = Relationships.create_relationship(oswald, rowena, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(lorraine, rowena, "parent", %{role: "mother"})

# Double first cousins marry
{:ok, _} = Relationships.create_relationship(archibald, rowena, "married", %{marriage_year: 1985})

# Their child = double pedigree collapse
quentin = p1.(%{given_name: "Quentin", surname: "Pemberton", gender: "male", birth_year: 1987})
{:ok, _} = Relationships.create_relationship(archibald, quentin, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(rowena, quentin, "parent", %{role: "mother"})

# ====================================================================
# TYPE 4 — Uncle marries niece (generational crossing)
#
# Desmond (Ashford) has a daughter. His brother Clifford married Ivy
# and has Leon. Leon's daughter marries Desmond's grandson. Actually,
# simpler: use a new mini-branch.
# We'll say Humphrey marries the daughter of his brother Gilbert.
# But Gilbert+Greta already have Wendell. Let's add a daughter.
# Actually we already used Gilbert/Humphrey/Greta for Type 2.
# Create a clean example with new people.
# ====================================================================

# New grandparents for this example
mortimer =
  p1.(%{
    given_name: "Mortimer",
    surname: "Kemp",
    gender: "male",
    birth_year: 1925,
    deceased: true,
    death_year: 1992
  })

delia =
  p1.(%{
    given_name: "Delia",
    surname: "Kemp",
    surname_at_birth: "Voss",
    gender: "female",
    birth_year: 1927,
    deceased: true,
    death_year: 2005
  })

{:ok, _} = Relationships.create_relationship(mortimer, delia, "married", %{marriage_year: 1946})

# Two sons
barton = p1.(%{given_name: "Barton", surname: "Kemp", gender: "male", birth_year: 1948})
# Uncle who will marry his niece:
reginald = p1.(%{given_name: "Reginald", surname: "Kemp", gender: "male", birth_year: 1950})

for child <- [barton, reginald] do
  {:ok, _} = Relationships.create_relationship(mortimer, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(delia, child, "parent", %{role: "mother"})
end

# Barton marries someone, has a daughter
hazel =
  p1.(%{
    given_name: "Hazel",
    surname: "Kemp",
    surname_at_birth: "Finch",
    gender: "female",
    birth_year: 1950
  })

{:ok, _} = Relationships.create_relationship(barton, hazel, "married", %{marriage_year: 1970})

dorinda = p1.(%{given_name: "Dorinda", surname: "Kemp", gender: "female", birth_year: 1972})
{:ok, _} = Relationships.create_relationship(barton, dorinda, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(hazel, dorinda, "parent", %{role: "mother"})

# Reginald (uncle) marries Dorinda (his niece)
{:ok, _} = Relationships.create_relationship(reginald, dorinda, "married", %{marriage_year: 1994})

# Their child — has a generational crossing
felix = p1.(%{given_name: "Felix", surname: "Kemp", gender: "male", birth_year: 1996})
{:ok, _} = Relationships.create_relationship(reginald, felix, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(dorinda, felix, "parent", %{role: "mother"})

# ====================================================================
# TYPE 5 — Siblings marry into same family (no pedigree collapse)
#
# Clifford married Ivy (already done for Type 1).
# Gilbert marries Greta (already done as divorced for Type 2).
# But the Type 5 point is: siblings from one family marry siblings
# from another, and their children do NOT intermarry.
# This is already shown by Clifford+Ivy and Desmond+Mabel from Type 1,
# if you look at their children OTHER than Leon and Sylvia.
# Let's add one more child to each couple to show the non-cycle case.
# ====================================================================

noreen = p1.(%{given_name: "Noreen", surname: "Ashford", gender: "female", birth_year: 1970})
{:ok, _} = Relationships.create_relationship(clifford, noreen, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(ivy, noreen, "parent", %{role: "mother"})

kent = p1.(%{given_name: "Kent", surname: "Ashford", gender: "male", birth_year: 1969})
{:ok, _} = Relationships.create_relationship(desmond, kent, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(mabel, kent, "parent", %{role: "mother"})

# Set Zara as the default focus person for this family
People.set_default_member(f1.id, zara.id)

IO.puts(
  "✓ Family 1 'Intermarried Clans' created (#{length(Ancestry.Repo.all(from fm in Ancestry.People.FamilyMember, where: fm.family_id == ^f1.id))} members)"
)

# ###########################################################################
#
#  FAMILY 2 — "Blended Saga"
#
#  A person (Victor) with 3 ex-partners and 1 current partner,
#  children from each union, plus solo children.
#
# ###########################################################################

{:ok, f2} = Families.create_family(org, %{name: "Blended Saga"})

p2 = fn attrs ->
  {:ok, p} = People.create_person(f2, attrs)
  p
end

# ---- Victor's parents (simple couple) ----

stanley =
  p2.(%{
    given_name: "Stanley",
    surname: "Holt",
    gender: "male",
    birth_year: 1935,
    deceased: true,
    death_year: 2010
  })

bridget =
  p2.(%{
    given_name: "Bridget",
    surname: "Holt",
    surname_at_birth: "Yates",
    gender: "female",
    birth_year: 1938
  })

{:ok, _} = Relationships.create_relationship(stanley, bridget, "married", %{marriage_year: 1958})

# ---- Victor (the center of the blended family) ----

victor = p2.(%{given_name: "Victor", surname: "Holt", gender: "male", birth_year: 1960})
{:ok, _} = Relationships.create_relationship(stanley, victor, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(bridget, victor, "parent", %{role: "mother"})

# Victor's sibling (to test lateral relatives)
nadine = p2.(%{given_name: "Nadine", surname: "Holt", gender: "female", birth_year: 1963})
{:ok, _} = Relationships.create_relationship(stanley, nadine, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(bridget, nadine, "parent", %{role: "mother"})

# ---- Ex-partner 1: Coral (divorced, 2 children) ----

coral =
  p2.(%{
    given_name: "Coral",
    surname: "Holt",
    surname_at_birth: "Fenn",
    gender: "female",
    birth_year: 1962
  })

{:ok, _} =
  Relationships.create_relationship(victor, coral, "divorced", %{
    marriage_year: 1982,
    divorce_year: 1988
  })

jasper = p2.(%{given_name: "Jasper", surname: "Holt", gender: "male", birth_year: 1983})
olive = p2.(%{given_name: "Olive", surname: "Holt", gender: "female", birth_year: 1986})

for child <- [jasper, olive] do
  {:ok, _} = Relationships.create_relationship(victor, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(coral, child, "parent", %{role: "mother"})
end

# ---- Ex-partner 2: Selene (separated, 1 child) ----

selene =
  p2.(%{
    given_name: "Selene",
    surname: "Holt",
    surname_at_birth: "Griggs",
    gender: "female",
    birth_year: 1965
  })

{:ok, _} =
  Relationships.create_relationship(victor, selene, "separated", %{
    marriage_year: 1990,
    separated_year: 1994
  })

linus = p2.(%{given_name: "Linus", surname: "Holt", gender: "male", birth_year: 1991})
{:ok, _} = Relationships.create_relationship(victor, linus, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(selene, linus, "parent", %{role: "mother"})

# ---- Ex-partner 3: Mirren (divorced, 3 children) ----

mirren =
  p2.(%{
    given_name: "Mirren",
    surname: "Holt",
    surname_at_birth: "Tovey",
    gender: "female",
    birth_year: 1968
  })

{:ok, _} =
  Relationships.create_relationship(victor, mirren, "divorced", %{
    marriage_year: 1996,
    divorce_year: 2003
  })

elowen = p2.(%{given_name: "Elowen", surname: "Holt", gender: "female", birth_year: 1997})
rufus = p2.(%{given_name: "Rufus", surname: "Holt", gender: "male", birth_year: 1999})
blythe = p2.(%{given_name: "Blythe", surname: "Holt", gender: "female", birth_year: 2001})

for child <- [elowen, rufus, blythe] do
  {:ok, _} = Relationships.create_relationship(victor, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(mirren, child, "parent", %{role: "mother"})
end

# ---- Current partner: Tamsin (married, 2 children) ----

tamsin =
  p2.(%{
    given_name: "Tamsin",
    surname: "Holt",
    surname_at_birth: "Pryce",
    gender: "female",
    birth_year: 1975
  })

{:ok, _} = Relationships.create_relationship(victor, tamsin, "married", %{marriage_year: 2005})

kit = p2.(%{given_name: "Kit", surname: "Holt", gender: "male", birth_year: 2006})
wren = p2.(%{given_name: "Wren", surname: "Holt", gender: "female", birth_year: 2009})

for child <- [kit, wren] do
  {:ok, _} = Relationships.create_relationship(victor, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(tamsin, child, "parent", %{role: "mother"})
end

# ---- Solo child (no known co-parent) ----

dale = p2.(%{given_name: "Dale", surname: "Holt", gender: "male", birth_year: 1988})
{:ok, _} = Relationships.create_relationship(victor, dale, "parent", %{role: "father"})

# ---- Give one of the ex-partner children their own family to test depth ----
# Jasper (eldest) married with kids
petra =
  p2.(%{
    given_name: "Petra",
    surname: "Holt",
    surname_at_birth: "Nye",
    gender: "female",
    birth_year: 1985
  })

{:ok, _} = Relationships.create_relationship(jasper, petra, "married", %{marriage_year: 2010})

arlo = p2.(%{given_name: "Arlo", surname: "Holt", gender: "male", birth_year: 2012})
tessa = p2.(%{given_name: "Tessa", surname: "Holt", gender: "female", birth_year: 2015})

for child <- [arlo, tessa] do
  {:ok, _} = Relationships.create_relationship(jasper, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(petra, child, "parent", %{role: "mother"})
end

# ---- Tamsin's parents (to test asymmetric ancestor depth) ----

clive = p2.(%{given_name: "Clive", surname: "Pryce", gender: "male", birth_year: 1948})

enid =
  p2.(%{
    given_name: "Enid",
    surname: "Pryce",
    surname_at_birth: "Marsh",
    gender: "female",
    birth_year: 1950
  })

{:ok, _} = Relationships.create_relationship(clive, enid, "married", %{marriage_year: 1972})
{:ok, _} = Relationships.create_relationship(clive, tamsin, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(enid, tamsin, "parent", %{role: "mother"})

People.set_default_member(f2.id, victor.id)

IO.puts(
  "✓ Family 2 'Blended Saga' created (#{length(Ancestry.Repo.all(from fm in Ancestry.People.FamilyMember, where: fm.family_id == ^f2.id))} members)"
)

# ###########################################################################
#
#  FAMILY 3 — "The Prolific Elders"
#
#  Grandparents with 13 children (common in 19th/early 20th century families).
#  Several children have spouses and children of their own.
#
# ###########################################################################

{:ok, f3} = Families.create_family(org, %{name: "The Prolific Elders"})

p3 = fn attrs ->
  {:ok, p} = People.create_person(f3, attrs)
  p
end

# ---- The prolific couple ----

cornelius =
  p3.(%{
    given_name: "Cornelius",
    surname: "Waverly",
    gender: "male",
    birth_year: 1880,
    deceased: true,
    death_year: 1955
  })

prudence =
  p3.(%{
    given_name: "Prudence",
    surname: "Waverly",
    surname_at_birth: "Thorne",
    gender: "female",
    birth_year: 1883,
    deceased: true,
    death_year: 1962
  })

{:ok, _} =
  Relationships.create_relationship(cornelius, prudence, "married", %{marriage_year: 1900})

# ---- Cornelius & Prudence's parents (great-grandparents for depth) ----

ambrose =
  p3.(%{
    given_name: "Ambrose",
    surname: "Waverly",
    gender: "male",
    birth_year: 1850,
    deceased: true,
    death_year: 1920
  })

esme =
  p3.(%{
    given_name: "Esme",
    surname: "Waverly",
    surname_at_birth: "Locke",
    gender: "female",
    birth_year: 1855,
    deceased: true,
    death_year: 1925
  })

{:ok, _} = Relationships.create_relationship(ambrose, esme, "married", %{marriage_year: 1875})
{:ok, _} = Relationships.create_relationship(ambrose, cornelius, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(esme, cornelius, "parent", %{role: "mother"})

# ---- The 13 children ----

children_data = [
  %{given_name: "Aldous", surname: "Waverly", gender: "male", birth_year: 1901},
  %{given_name: "Beatrix", surname: "Waverly", gender: "female", birth_year: 1903},
  %{given_name: "Clement", surname: "Waverly", gender: "male", birth_year: 1904},
  %{given_name: "Dorothea", surname: "Waverly", gender: "female", birth_year: 1906},
  %{given_name: "Edmund", surname: "Waverly", gender: "male", birth_year: 1907},
  %{given_name: "Florence", surname: "Waverly", gender: "female", birth_year: 1909},
  %{
    given_name: "Godwin",
    surname: "Waverly",
    gender: "male",
    birth_year: 1910,
    deceased: true,
    death_year: 1944
  },
  %{given_name: "Harriet", surname: "Waverly", gender: "female", birth_year: 1912},
  %{given_name: "Irving", surname: "Waverly", gender: "male", birth_year: 1914},
  %{given_name: "Josephine", surname: "Waverly", gender: "female", birth_year: 1916},
  %{given_name: "Kenneth", surname: "Waverly", gender: "male", birth_year: 1918},
  %{given_name: "Lillian", surname: "Waverly", gender: "female", birth_year: 1920},
  %{given_name: "Montague", surname: "Waverly", gender: "male", birth_year: 1922}
]

children =
  Enum.map(children_data, fn attrs ->
    child = p3.(attrs)
    {:ok, _} = Relationships.create_relationship(cornelius, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(prudence, child, "parent", %{role: "mother"})
    child
  end)

[
  aldous,
  beatrix,
  clement,
  dorothea,
  edmund,
  florence,
  _godwin,
  harriet,
  irving,
  josephine,
  kenneth,
  lillian,
  montague
] = children

# ---- Give several children their own families ----

# Aldous married, 3 children
myrtle =
  p3.(%{
    given_name: "Myrtle",
    surname: "Waverly",
    surname_at_birth: "Croft",
    gender: "female",
    birth_year: 1904
  })

{:ok, _} = Relationships.create_relationship(aldous, myrtle, "married", %{marriage_year: 1925})

for {name, year, gender} <- [
      {"Percival", 1926, "male"},
      {"Rosalind", 1928, "female"},
      {"Tobias", 1930, "male"}
    ] do
  child = p3.(%{given_name: name, surname: "Waverly", gender: gender, birth_year: year})
  {:ok, _} = Relationships.create_relationship(aldous, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(myrtle, child, "parent", %{role: "mother"})
end

# Clement married, 2 children
vivian =
  p3.(%{
    given_name: "Vivian",
    surname: "Waverly",
    surname_at_birth: "Peel",
    gender: "female",
    birth_year: 1906
  })

{:ok, _} = Relationships.create_relationship(clement, vivian, "married", %{marriage_year: 1928})

for {name, year, gender} <- [{"Nigel", 1929, "male"}, {"Vera", 1931, "female"}] do
  child = p3.(%{given_name: name, surname: "Waverly", gender: gender, birth_year: year})
  {:ok, _} = Relationships.create_relationship(clement, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(vivian, child, "parent", %{role: "mother"})
end

# Edmund married, 4 children
gladys =
  p3.(%{
    given_name: "Gladys",
    surname: "Waverly",
    surname_at_birth: "Oakley",
    gender: "female",
    birth_year: 1910
  })

{:ok, _} = Relationships.create_relationship(edmund, gladys, "married", %{marriage_year: 1932})

for {name, year, gender} <- [
      {"Arthur", 1933, "male"},
      {"Constance", 1935, "female"},
      {"Donald", 1937, "male"},
      {"Elsie", 1939, "female"}
    ] do
  child = p3.(%{given_name: name, surname: "Waverly", gender: gender, birth_year: year})
  {:ok, _} = Relationships.create_relationship(edmund, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(gladys, child, "parent", %{role: "mother"})
end

# Irving married, 2 children
sybil =
  p3.(%{
    given_name: "Sybil",
    surname: "Waverly",
    surname_at_birth: "Rowe",
    gender: "female",
    birth_year: 1917
  })

{:ok, _} = Relationships.create_relationship(irving, sybil, "married", %{marriage_year: 1938})

for {name, year, gender} <- [{"Maxwell", 1940, "male"}, {"Ursula", 1942, "female"}] do
  child = p3.(%{given_name: name, surname: "Waverly", gender: gender, birth_year: year})
  {:ok, _} = Relationships.create_relationship(irving, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(sybil, child, "parent", %{role: "mother"})
end

# Josephine married into another family, 1 child
otis = p3.(%{given_name: "Otis", surname: "Bancroft", gender: "male", birth_year: 1914})
{:ok, _} = Relationships.create_relationship(otis, josephine, "married", %{marriage_year: 1940})

harper = p3.(%{given_name: "Harper", surname: "Bancroft", gender: "female", birth_year: 1942})
{:ok, _} = Relationships.create_relationship(otis, harper, "parent", %{role: "father"})
{:ok, _} = Relationships.create_relationship(josephine, harper, "parent", %{role: "mother"})

# Montague (youngest) married, 2 children — set as default focus
lenora =
  p3.(%{
    given_name: "Lenora",
    surname: "Waverly",
    surname_at_birth: "Ives",
    gender: "female",
    birth_year: 1924
  })

{:ok, _} = Relationships.create_relationship(montague, lenora, "married", %{marriage_year: 1944})

walt = p3.(%{given_name: "Walt", surname: "Waverly", gender: "male", birth_year: 1946})
iris_w = p3.(%{given_name: "Iris", surname: "Waverly", gender: "female", birth_year: 1948})

for child <- [walt, iris_w] do
  {:ok, _} = Relationships.create_relationship(montague, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(lenora, child, "parent", %{role: "mother"})
end

People.set_default_member(f3.id, montague.id)

IO.puts(
  "✓ Family 3 'The Prolific Elders' created (#{length(Ancestry.Repo.all(from fm in Ancestry.People.FamilyMember, where: fm.family_id == ^f3.id))} members)"
)

IO.puts("\nDone! Organization '#{org.name}' created with 3 families.")
