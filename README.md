# Graph

In the narrow sense, a "genealogy" or a "family tree" traces the descendants of
one person, whereas a "family history" traces the ancestors of one person, but
the terms are often used interchangeably. A family history may include
additional biographical information, family traditions, and the like.


Concepts
========
Genealogy
* Person
* Family Tree
* Family History

Data Types
==========
* Gender (unset | male | female | other)
* Person Identifier (simple hash e.g. PMS9-XB6) 7 characters P[A-Z0-9]{6}
* Date Range (Day | Day and, Month | Day and, Month and Year | Month and Year | Year | Month)
* RelationshipType (

Models
==========
* Vitals
    - Id (Person Identifier)
    - Given Names (Nullable String)
    - Surnames now (Nullable String)
    - Surnames at birth (Nullable String)
    - Gender (Gender)
    - Birth Date (Date Range)
    - Death Date (Date Range)
    - IsDead (Boolean)

* Relationship
    - PersonId
    - Type

* create_genealogy(identifier)
* add_person(vitals)
* add_parent(mother(vitals))
* add_parent(father(vitals))
