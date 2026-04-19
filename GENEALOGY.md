# Kinship Terminology Reference

Complete mapping between the coordinate system `(steps_a, steps_b)` used by `Ancestry.Kinship` and the correct terminology in English and Spanish, including gendered forms.

## Coordinate System

Every kinship relationship between two people (A and B) is described by two numbers:

- **steps_a**: Person A's generational distance to the Most Recent Common Ancestor (MRCA)
- **steps_b**: Person B's generational distance to the MRCA

The relationship label describes **what A is to B** (e.g., "A is B's uncle").

### Derived values

| Value | Formula | Meaning |
|---|---|---|
| **direction** | `steps_a < steps_b` → ascending, `steps_a > steps_b` → descending, `==` → same | Which generation A is in relative to B |
| **removed** | `abs(steps_a - steps_b)` | Generational offset |
| **ordinal_n** | `min(steps_a, steps_b)` | Collateral distance (0 = direct line, 1 = sibling/uncle/nephew, 2+ = cousin/extended) |
| **degree** | `min(steps_a, steps_b) - 1` | Cousin degree (for same-generation cousins) |

### Ordinal numbering (Spanish)

When ordinals appear as suffixes (e.g., "Tío **Segundo**", "Primo **Tercero**"), they agree in gender:

| N | Masculine | Feminine |
|---|---|---|
| 2 | segundo | segunda |
| 3 | tercero | tercera |
| 4 | cuarto | cuarta |
| 5 | quinto | quinta |
| 6 | sexto | sexta |
| 7 | séptimo | séptima |
| 8 | octavo | octava |

> For ordinal_n = 1, the suffix is omitted (just "Tío", "Sobrino", etc.).
> For cousins, degree = 1 also omits the suffix (just "Primo/Prima").

---

## Complete Kinship Grid — Spanish (Masculine)

Each cell shows what **person A is to person B**. Rows = steps_a, Columns = steps_b.

| A↓ B→ | **0** | **1** | **2** | **3** | **4** | **5** | **6** | **7** |
|---|---|---|---|---|---|---|---|---|
| **0** | — | Padre | Abuelo | Bisabuelo | Tatarabuelo | Trastatarabuelo | 5° Abuelo | 6° Abuelo |
| **1** | Hijo | Hermano | Tío | Tío Abuelo | Tío Bisabuelo | Tío Tatarabuelo | Tío Trastatarabuelo | Tío 6° Abuelo |
| **2** | Nieto | Sobrino | Primo | Tío 2° | Tío Abuelo 2° | Tío Bisabuelo 2° | Tío Tatarabuelo 2° | Tío Trastatarabuelo 2° |
| **3** | Bisnieto | Sobrino Nieto | Sobrino 2° | Primo 2° | Tío 3° | Tío Abuelo 3° | Tío Bisabuelo 3° | Tío Tatarabuelo 3° |
| **4** | Tataranieto | Sobrino Bisnieto | Sobrino Nieto 2° | Sobrino 3° | Primo 3° | Tío 4° | Tío Abuelo 4° | Tío Bisabuelo 4° |
| **5** | Trastataranieto | Sobrino Tataranieto | Sobrino Bisnieto 2° | Sobrino Nieto 3° | Sobrino 4° | Primo 4° | Tío 5° | Tío Abuelo 5° |
| **6** | 5° Nieto | Sobrino Trastataranieto | Sobrino Tataranieto 2° | Sobrino Bisnieto 3° | Sobrino Nieto 4° | Sobrino 5° | Primo 5° | Tío 6° |
| **7** | 6° Nieto | Sobrino 5° Nieto | Sobrino Trastataranieto 2° | Sobrino Tataranieto 3° | Sobrino Bisnieto 4° | Sobrino Nieto 5° | Sobrino 6° | Primo 6° |

> The diagonal (steps_a == steps_b) is always same-generation: Hermano, Primo, Primo 2°, etc.
> Above the diagonal → ascending (Tío direction). Below → descending (Sobrino direction).

## Complete Kinship Grid — English

| A↓ B→ | **0** | **1** | **2** | **3** | **4** | **5** | **6** | **7** |
|---|---|---|---|---|---|---|---|---|
| **0** | — | Parent | Grandparent | Gt Grandparent | Gt Gt Grandparent | 3rd Gt GP | 4th Gt GP | 5th Gt GP |
| **1** | Child | Sibling | Uncle/Aunt | Gt Uncle/Aunt | Gt Grand U/A | 1st Gt Grand U/A | 2nd Gt Grand U/A | 3rd Gt Grand U/A |
| **2** | Grandchild | Nephew/Niece | 1st Cousin | 1st C 1× Rem | 1st C 2× Rem | 1st C 3× Rem | 1st C 4× Rem | 1st C 5× Rem |
| **3** | Gt Grandchild | Grand N/N | 1st C 1× Rem | 2nd Cousin | 2nd C 1× Rem | 2nd C 2× Rem | 2nd C 3× Rem | 2nd C 4× Rem |
| **4** | Gt Gt Grandchild | Gt Grand N/N | 1st C 2× Rem | 2nd C 1× Rem | 3rd Cousin | 3rd C 1× Rem | 3rd C 2× Rem | 3rd C 3× Rem |
| **5** | 3rd Gt GC | 1st Gt Grand N/N | 1st C 3× Rem | 2nd C 2× Rem | 3rd C 1× Rem | 4th Cousin | 4th C 1× Rem | 4th C 2× Rem |
| **6** | 4th Gt GC | 2nd Gt Grand N/N | 1st C 4× Rem | 2nd C 3× Rem | 3rd C 2× Rem | 4th C 1× Rem | 5th Cousin | 5th C 1× Rem |
| **7** | 5th Gt GC | 3rd Gt Grand N/N | 1st C 5× Rem | 2nd C 4× Rem | 3rd C 3× Rem | 4th C 2× Rem | 5th C 1× Rem | 6th Cousin |

> English "Nth Cousin, M Times Removed" is direction-agnostic — (2,3) and (3,2) produce the same label.
> Spanish distinguishes direction: (2,3) = Tío 2° vs (3,2) = Sobrino 2°.

---

## Detailed Tables by Relationship Type

### Direct Line — Ascending (A is B's ancestor)

| (a,b) | English | Male | Female | Unknown |
|---|---|---|---|---|
| (0,1) | Parent | Padre | Madre | Padre/Madre |
| (0,2) | Grandparent | Abuelo | Abuela | Abuelo/a |
| (0,3) | Great Grandparent | Bisabuelo | Bisabuela | Bisabuelo/a |
| (0,4) | Great Great Grandparent | Tatarabuelo | Tatarabuela | Tatarabuelo/a |
| (0,5) | 3rd Great Grandparent | Trastatarabuelo | Trastatarabuela | Trastatarabuelo/a |
| (0,6) | 4th Great Grandparent | 5° Abuelo | 5° Abuela | 5° Abuelo/a |
| (0,7) | 5th Great Grandparent | 6° Abuelo | 6° Abuela | 6° Abuelo/a |
| (0,8) | 6th Great Grandparent | 7° Abuelo | 7° Abuela | 7° Abuelo/a |
| (0,9) | 7th Great Grandparent | 8° Abuelo | 8° Abuela | 8° Abuelo/a |

> **Formula:** ordinal = steps_b − 1 (counting from Abuelo). Named forms up to generation 5 (Trastatarabuelo), then N° Abuelo/a.

### Direct Line — Descending (A is B's descendant)

| (a,b) | English | Male | Female | Unknown |
|---|---|---|---|---|
| (1,0) | Child | Hijo | Hija | Hijo/a |
| (2,0) | Grandchild | Nieto | Nieta | Nieto/a |
| (3,0) | Great Grandchild | Bisnieto | Bisnieta | Bisnieto/a |
| (4,0) | Great Great Grandchild | Tataranieto | Tataranieta | Tataranieto/a |
| (5,0) | 3rd Great Grandchild | Trastataranieto | Trastataranieta | Trastataranieto/a |
| (6,0) | 4th Great Grandchild | 5° Nieto | 5° Nieta | 5° Nieto/a |
| (7,0) | 5th Great Grandchild | 6° Nieto | 6° Nieta | 6° Nieto/a |
| (8,0) | 6th Great Grandchild | 7° Nieto | 7° Nieta | 7° Nieto/a |
| (9,0) | 7th Great Grandchild | 8° Nieto | 8° Nieta | 8° Nieto/a |

> **Formula:** ordinal = steps_a − 1. Same naming pattern as ancestors but with Nieto/Nieta.

### Siblings

| (a,b) | English | Male | Female | Unknown |
|---|---|---|---|---|
| (1,1) | Sibling | Hermano | Hermana | Hermano/a |
| (1,1) half | Half-Sibling | Medio hermano | Media hermana | Medio/a hermano/a |

### First Collateral Line — Ascending (Uncle/Aunt chain, steps_a = 1)

| (a,b) | removed | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (1,2) | 1 | Uncle/Aunt | Tío | Tía | Tío/a |
| (1,3) | 2 | Great Uncle/Aunt | Tío abuelo | Tía abuela | Tío/a abuelo/a |
| (1,4) | 3 | Great Grand Uncle/Aunt | Tío bisabuelo | Tía bisabuela | Tío/a bisabuelo/a |
| (1,5) | 4 | 1st Gt Grand Uncle/Aunt | Tío tatarabuelo | Tía tatarabuela | Tío/a tatarabuelo/a |
| (1,6) | 5 | 2nd Gt Grand Uncle/Aunt | Tío trastatarabuelo | Tía trastatarabuela | Tío/a trastatarabuelo/a |
| (1,7) | 6 | 3rd Gt Grand Uncle/Aunt | Tío 6° abuelo | Tía 6° abuela | Tío/a 6° abuelo/a |

> **Generation suffix** uses the ancestor name for (removed) generations: "" (1), Abuelo (2), Bisabuelo (3), Tatarabuelo (4), Trastatarabuelo (5), then N° Abuelo where N = removed.

### First Collateral Line — Descending (Nephew/Niece chain, steps_b = 1)

| (a,b) | removed | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (2,1) | 1 | Nephew/Niece | Sobrino | Sobrina | Sobrino/a |
| (3,1) | 2 | Grand Nephew/Niece | Sobrino nieto | Sobrina nieta | Sobrino/a nieto/a |
| (4,1) | 3 | Great Grand Nephew/Niece | Sobrino bisnieto | Sobrina bisnieta | Sobrino/a bisnieto/a |
| (5,1) | 4 | 1st Gt Grand Nephew/Niece | Sobrino tataranieto | Sobrina tataranieta | Sobrino/a tataranieto/a |
| (6,1) | 5 | 2nd Gt Grand Nephew/Niece | Sobrino trastataranieto | Sobrina trastataranieta | Sobrino/a trastataranieto/a |
| (7,1) | 6 | 3rd Gt Grand Nephew/Niece | Sobrino 6° nieto | Sobrina 6° nieta | Sobrino/a 6° nieto/a |

> **Generation suffix** uses the descendant name for (removed) generations: "" (1), Nieto (2), Bisnieto (3), Tataranieto (4), Trastataranieto (5), then N° Nieto where N = removed.

### Same-Generation Cousins (removed = 0)

| (a,b) | degree | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (2,2) | 1 | First Cousin | Primo | Prima | Primo/a |
| (3,3) | 2 | Second Cousin | Primo segundo | Prima segunda | Primo/a segundo/a |
| (4,4) | 3 | Third Cousin | Primo tercero | Prima tercera | Primo/a tercero/a |
| (5,5) | 4 | Fourth Cousin | Primo cuarto | Prima cuarta | Primo/a cuarto/a |
| (6,6) | 5 | Fifth Cousin | Primo quinto | Prima quinta | Primo/a quinto/a |
| (7,7) | 6 | Sixth Cousin | Primo sexto | Prima sexta | Primo/a sexto/a |

> **Pattern:** degree = ordinal_n − 1. Degree 1 has no suffix (just "Primo/a"). Degree ≥ 2 appends a gendered ordinal.

### Removed Cousins — Ascending (Tío direction, steps_a < steps_b, both ≥ 2)

**removed = 1 (one generation apart, A is older):**

| (a,b) | ordinal_n | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (2,3) | 2 | 1st Cousin 1× Removed | Tío segundo | Tía segunda | Tío/a segundo/a |
| (3,4) | 3 | 2nd Cousin 1× Removed | Tío tercero | Tía tercera | Tío/a tercero/a |
| (4,5) | 4 | 3rd Cousin 1× Removed | Tío cuarto | Tía cuarta | Tío/a cuarto/a |
| (5,6) | 5 | 4th Cousin 1× Removed | Tío quinto | Tía quinta | Tío/a quinto/a |
| (6,7) | 6 | 5th Cousin 1× Removed | Tío sexto | Tía sexta | Tío/a sexto/a |

**removed = 2 (two generations apart, A is older):**

| (a,b) | ordinal_n | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (2,4) | 2 | 1st Cousin 2× Removed | Tío abuelo segundo | Tía abuela segunda | Tío/a abuelo/a segundo/a |
| (3,5) | 3 | 2nd Cousin 2× Removed | Tío abuelo tercero | Tía abuela tercera | Tío/a abuelo/a tercero/a |
| (4,6) | 4 | 3rd Cousin 2× Removed | Tío abuelo cuarto | Tía abuela cuarta | Tío/a abuelo/a cuarto/a |
| (5,7) | 5 | 4th Cousin 2× Removed | Tío abuelo quinto | Tía abuela quinta | Tío/a abuelo/a quinto/a |

**removed = 3 (three generations apart, A is older):**

| (a,b) | ordinal_n | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (2,5) | 2 | 1st Cousin 3× Removed | Tío bisabuelo segundo | Tía bisabuela segunda | Tío/a bisabuelo/a segundo/a |
| (3,6) | 3 | 2nd Cousin 3× Removed | Tío bisabuelo tercero | Tía bisabuela tercera | Tío/a bisabuelo/a tercero/a |
| (4,7) | 4 | 3rd Cousin 3× Removed | Tío bisabuelo cuarto | Tía bisabuela cuarta | Tío/a bisabuelo/a cuarto/a |

**removed = 4 (four generations apart, A is older):**

| (a,b) | ordinal_n | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (2,6) | 2 | 1st Cousin 4× Removed | Tío tatarabuelo segundo | Tía tatarabuela segunda | Tío/a tatarabuelo/a segundo/a |
| (3,7) | 3 | 2nd Cousin 4× Removed | Tío tatarabuelo tercero | Tía tatarabuela tercera | Tío/a tatarabuelo/a tercero/a |

### Removed Cousins — Descending (Sobrino direction, steps_a > steps_b, both ≥ 2)

**removed = 1 (one generation apart, A is younger):**

| (a,b) | ordinal_n | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (3,2) | 2 | 1st Cousin 1× Removed | Sobrino segundo | Sobrina segunda | Sobrino/a segundo/a |
| (4,3) | 3 | 2nd Cousin 1× Removed | Sobrino tercero | Sobrina tercera | Sobrino/a tercero/a |
| (5,4) | 4 | 3rd Cousin 1× Removed | Sobrino cuarto | Sobrina cuarta | Sobrino/a cuarto/a |
| (6,5) | 5 | 4th Cousin 1× Removed | Sobrino quinto | Sobrina quinta | Sobrino/a quinto/a |
| (7,6) | 6 | 5th Cousin 1× Removed | Sobrino sexto | Sobrina sexta | Sobrino/a sexto/a |

**removed = 2 (two generations apart, A is younger):**

| (a,b) | ordinal_n | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (4,2) | 2 | 1st Cousin 2× Removed | Sobrino nieto segundo | Sobrina nieta segunda | Sobrino/a nieto/a segundo/a |
| (5,3) | 3 | 2nd Cousin 2× Removed | Sobrino nieto tercero | Sobrina nieta tercera | Sobrino/a nieto/a tercero/a |
| (6,4) | 4 | 3rd Cousin 2× Removed | Sobrino nieto cuarto | Sobrina nieta cuarta | Sobrino/a nieto/a cuarto/a |
| (7,5) | 5 | 4th Cousin 2× Removed | Sobrino nieto quinto | Sobrina nieta quinta | Sobrino/a nieto/a quinto/a |

**removed = 3 (three generations apart, A is younger):**

| (a,b) | ordinal_n | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (5,2) | 2 | 1st Cousin 3× Removed | Sobrino bisnieto segundo | Sobrina bisnieta segunda | Sobrino/a bisnieto/a segundo/a |
| (6,3) | 3 | 2nd Cousin 3× Removed | Sobrino bisnieto tercero | Sobrina bisnieta tercera | Sobrino/a bisnieto/a tercero/a |
| (7,4) | 4 | 3rd Cousin 3× Removed | Sobrino bisnieto cuarto | Sobrina bisnieta cuarta | Sobrino/a bisnieto/a cuarto/a |

**removed = 4 (four generations apart, A is younger):**

| (a,b) | ordinal_n | English | Male | Female | Unknown |
|---|---|---|---|---|---|
| (6,2) | 2 | 1st Cousin 4× Removed | Sobrino tataranieto segundo | Sobrina tataranieta segunda | Sobrino/a tataranieto/a segundo/a |
| (7,3) | 3 | 2nd Cousin 4× Removed | Sobrino tataranieto tercero | Sobrina tataranieta tercera | Sobrino/a tataranieto/a tercero/a |

### Half-Relationships

The half prefix applies when persons A and B share only **one** common ancestor at the MRCA generation (instead of two). It prepends to any label:

| English | Male | Female | Unknown |
|---|---|---|---|
| Half-{label} | Medio {label} | Media {label} | Medio/a {label} |

Examples: "Medio primo segundo" (male half second cousin), "Media prima tercera" (female half third cousin).

---

## In-Laws — Familia Política

In-law relationships are formed through marriage rather than blood. They do not use the MRCA coordinate system.

### Core In-Law Terms

| Relationship | English (m) | English (f) | English (unknown) | Spanish (m) | Spanish (f) | Spanish (unknown) |
|---|---|---|---|---|---|---|
| Spouse | Husband | Wife | Spouse | Esposo | Esposa | Cónyuge |
| Parent-in-law | Father-in-law | Mother-in-law | Parent-in-law | Suegro | Suegra | Suegro/a |
| Child-in-law | Son-in-law | Daughter-in-law | Child-in-law | Yerno | Nuera | Yerno/Nuera |
| Sibling-in-law | Brother-in-law | Sister-in-law | Sibling-in-law | Cuñado | Cuñada | Cuñado/a |
| Grandparent-in-law | Grandfather-in-law | Grandmother-in-law | Grandparent-in-law | Abuelo político | Abuela política | Abuelo/a político/a |

> Note: "Yerno" (son-in-law) and "Nuera" (daughter-in-law) are distinct words, not gendered forms of the same root. In English, both are formed with the "-in-law" suffix.

### Extended In-Law Terms

| Relationship | English (m) | English (f) | Spanish (m) | Spanish (f) |
|---|---|---|---|---|
| Uncle/Aunt-in-law | Uncle-in-law | Aunt-in-law | Tío político | Tía política |
| Cousin-in-law | Cousin-in-law | Cousin-in-law | Primo político | Prima política |
| Nephew/Niece-in-law | Nephew-in-law | Niece-in-law | Sobrino político | Sobrina política |

### Additional In-Law Terms (common in Spanish)

| Spanish | English equivalent | Definition |
|---|---|---|
| Consuegro / Consuegra | Co-parent-in-law | Parent of your child's spouse |
| Concuñado / Concuñada | Co-sibling-in-law | Spouse of your spouse's sibling |

---

## Label Construction Formula

Given `(steps_a, steps_b, gender)`, the Spanish label is constructed as follows:

### 1. Direct Line (ordinal_n = 0)

```
ascending (steps_a = 0):  ancestor_name(steps_b, gender)
descending (steps_b = 0): descendant_name(steps_a, gender)
```

Where `ancestor_name` / `descendant_name`:

| N | Ancestor (m) | Ancestor (f) | Descendant (m) | Descendant (f) |
|---|---|---|---|---|
| 1 | Padre | Madre | Hijo | Hija |
| 2 | Abuelo | Abuela | Nieto | Nieta |
| 3 | Bisabuelo | Bisabuela | Bisnieto | Bisnieta |
| 4 | Tatarabuelo | Tatarabuela | Tataranieto | Tataranieta |
| 5 | Trastatarabuelo | Trastatarabuela | Trastataranieto | Trastataranieta |
| ≥6 | (N−1)° Abuelo | (N−1)° Abuela | (N−1)° Nieto | (N−1)° Nieta |

### 2. Same Generation (removed = 0, ordinal_n ≥ 1)

```
ordinal_n = 1:  Hermano / Hermana
ordinal_n ≥ 2: "Primo/a" + degree_suffix(ordinal_n − 1, gender)
```

Where `degree_suffix(1) = ""`, `degree_suffix(2) = "segundo/a"`, etc.

### 3. Different Generation (removed ≥ 1)

```
label = base(direction, gender)
      + generation_suffix(removed, direction, gender)
      + ordinal_suffix(ordinal_n, gender)
```

**Base term (direction + gender):**

| Direction | Male | Female |
|---|---|---|
| ascending (A older) | Tío | Tía |
| descending (A younger) | Sobrino | Sobrina |

**Generation suffix (how many generations apart beyond 1):**

| removed | Ascending suffix (m/f) | Descending suffix (m/f) |
|---|---|---|
| 1 | _(none)_ | _(none)_ |
| 2 | abuelo / abuela | nieto / nieta |
| 3 | bisabuelo / bisabuela | bisnieto / bisnieta |
| 4 | tatarabuelo / tatarabuela | tataranieto / tataranieta |
| 5 | trastatarabuelo / trastatarabuela | trastataranieto / trastataranieta |
| ≥6 | N° abuelo / N° abuela (N = removed) | N° nieto / N° nieta (N = removed) |

**Ordinal suffix (collateral distance):**

| ordinal_n | Suffix |
|---|---|
| 1 | _(none — already handled by first collateral line)_ |
| 2 | segundo / segunda |
| 3 | tercero / tercera |
| N ≥ 4 | gendered ordinal of N |

### Example: (4,7) male

```
ordinal_n = min(4,7) = 4
removed = abs(4−7) = 3
direction = ascending (4 < 7)

base = "Tío"
generation_suffix = bisabuelo (removed=3, ascending, male)
ordinal_suffix = cuarto (ordinal_n=4, male)

→ "Tío bisabuelo cuarto"
```

English equivalent: "3rd Cousin, 3 Times Removed"

---

## References

- [Spanish Genealogical Word List — FamilySearch](https://www.familysearch.org/en/wiki/Spanish_Genealogical_Word_List)
- [Great-great-...-great-grandparents — SpanishDict Answers](https://www.spanishdict.com/answers/112188/great-great-...-great-grandparents)
- [Anexo: Nomenclatura de parentesco en español — Wikipedia](https://es.wikipedia.org/wiki/Anexo:Nomenclatura_de_parentesco_en_espa%C3%B1ol)
- [Grado de parentesco — Wikipedia](https://es.wikipedia.org/wiki/Grado_de_parentesco)
- [Ancestry — Spanish Genealogy Terminology](https://support.ancestry.com/s/article/Spanish-Genealogy-Terminology?language=en_US)
- [first cousin once removed — SpanishDict](https://www.spanishdict.com/translate/first%20cousin%20once%20removed)
