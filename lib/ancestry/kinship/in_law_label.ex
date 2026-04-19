defmodule Ancestry.Kinship.InLawLabel do
  @moduledoc """
  Produces human-readable in-law kinship labels.

  Core terms (Suegro/a, Yerno/Nuera, Cuñado/a) use dedicated Gettext msgids.
  Extended terms construct the blood label then append "político/a" / "-in-law".

  The label describes "what person A is to person B" — gendered by person A's gender.
  """

  defp normalize_gender("male"), do: "male"
  defp normalize_gender("female"), do: "female"
  defp normalize_gender(_), do: "other"

  defp t(g, msgid), do: Gettext.pgettext(Web.Gettext, g, msgid)
  defp t(g, msgid, bindings), do: Gettext.pgettext(Web.Gettext, g, msgid, bindings)

  @doc """
  Formats an in-law label.

  For spouse: pass `(:spouse, :spouse, gender)`.
  For partner-hop results: pass `(steps_a, steps_b, gender)` from the blood BFS.
  """
  def format(:spouse, :spouse, gender) do
    g = normalize_gender(gender)
    t(g, "Spouse")
  end

  def format(steps_a, steps_b, gender) do
    g = normalize_gender(gender)
    classify(steps_a, steps_b, g)
  end

  # Core special terms
  defp classify(0, 1, g), do: t(g, "Parent-in-law")
  defp classify(1, 0, g), do: t(g, "Child-in-law")
  defp classify(1, 1, g), do: t(g, "Sibling-in-law")

  # Everything else — locale-aware
  defp classify(steps_a, steps_b, g) do
    locale = Gettext.get_locale(Web.Gettext)

    if String.starts_with?(locale, "es") do
      spanish_in_law_label(steps_a, steps_b, g)
    else
      english_in_law_label(steps_a, steps_b, g)
    end
  end

  # --- English in-law labels ---

  # Direct line ascending
  defp english_in_law_label(0, 2, g), do: t(g, "Grandparent-in-law")
  defp english_in_law_label(0, 3, g), do: t(g, "Great Grandparent-in-law")
  defp english_in_law_label(0, 4, g), do: t(g, "Great Great Grandparent-in-law")
  defp english_in_law_label(0, 5, g), do: t(g, "3rd Great Grandparent-in-law")

  defp english_in_law_label(0, steps_b, g) when steps_b >= 6 do
    t(g, "%{nth} Great Grandparent-in-law", nth: numeric_ordinal(steps_b - 2))
  end

  # Direct line descending
  defp english_in_law_label(2, 0, g), do: t(g, "Grandchild-in-law")
  defp english_in_law_label(3, 0, g), do: t(g, "Great Grandchild-in-law")
  defp english_in_law_label(4, 0, g), do: t(g, "Great Great Grandchild-in-law")
  defp english_in_law_label(5, 0, g), do: t(g, "3rd Great Grandchild-in-law")

  defp english_in_law_label(steps_a, 0, g) when steps_a >= 6 do
    t(g, "%{nth} Great Grandchild-in-law", nth: numeric_ordinal(steps_a - 2))
  end

  # Uncle/Aunt chain
  defp english_in_law_label(1, 2, g), do: t(g, "Uncle/Aunt-in-law")
  defp english_in_law_label(1, 3, g), do: t(g, "Great Uncle/Aunt-in-law")
  defp english_in_law_label(1, 4, g), do: t(g, "Great Grand Uncle/Aunt-in-law")

  defp english_in_law_label(1, steps_b, g) when steps_b >= 5 do
    t(g, "%{nth} Great Grand Uncle/Aunt-in-law", nth: numeric_ordinal(steps_b - 4))
  end

  # Nephew/Niece chain
  defp english_in_law_label(2, 1, g), do: t(g, "Nephew/Niece-in-law")
  defp english_in_law_label(3, 1, g), do: t(g, "Grand Nephew/Niece-in-law")
  defp english_in_law_label(4, 1, g), do: t(g, "Great Grand Nephew/Niece-in-law")

  defp english_in_law_label(steps_a, 1, g) when steps_a >= 5 do
    t(g, "%{nth} Great Grand Nephew/Niece-in-law", nth: numeric_ordinal(steps_a - 4))
  end

  # Cousins (same gen and removed)
  defp english_in_law_label(steps_a, steps_b, g) when steps_a >= 2 and steps_b >= 2 do
    degree = min(steps_a, steps_b) - 1

    if steps_a == steps_b do
      if degree == 1 do
        t(g, "Cousin-in-law")
      else
        degree_str = ordinal(degree, g)
        t(g, "%{degree} Cousin-in-law", degree: degree_str)
      end
    else
      degree_str = ordinal(degree, g)
      removed = abs(steps_a - steps_b)

      removed_str =
        cond do
          removed == 1 -> t(g, ", Once Removed")
          removed == 2 -> t(g, ", Twice Removed")
          true -> t(g, ", %{count} Times Removed", count: removed)
        end

      t(g, "%{degree} Cousin%{removed}-in-law", degree: degree_str, removed: removed_str)
    end
  end

  # --- Spanish in-law labels ---
  defp spanish_in_law_label(steps_a, steps_b, g) do
    blood = spanish_blood_label(steps_a, steps_b, g)
    suffix = politico_suffix(g)
    "#{blood} #{suffix}"
  end

  # Direct line ascending
  defp spanish_blood_label(0, 1, g), do: spanish_parent(g)
  defp spanish_blood_label(0, 2, g), do: spanish_abuelo(g)
  defp spanish_blood_label(0, 3, g), do: spanish_bisabuelo(g)
  defp spanish_blood_label(0, 4, g), do: spanish_tatarabuelo(g)
  defp spanish_blood_label(0, 5, g), do: spanish_trastatarabuelo(g)

  defp spanish_blood_label(0, steps_b, g) when steps_b >= 6,
    do: "#{steps_b - 1}° #{spanish_abuelo(g)}"

  # Direct line descending
  defp spanish_blood_label(1, 0, g), do: spanish_child(g)
  defp spanish_blood_label(2, 0, g), do: spanish_nieto(g)
  defp spanish_blood_label(3, 0, g), do: spanish_bisnieto(g)
  defp spanish_blood_label(4, 0, g), do: spanish_tataranieto(g)
  defp spanish_blood_label(5, 0, g), do: spanish_trastataranieto(g)

  defp spanish_blood_label(steps_a, 0, g) when steps_a >= 6,
    do: "#{steps_a - 1}° #{spanish_nieto(g)}"

  # Siblings
  defp spanish_blood_label(1, 1, g), do: spanish_hermano(g)

  # Uncle/Aunt, Nephew/Niece chains + cousins
  defp spanish_blood_label(steps_a, steps_b, g) when steps_a >= 1 and steps_b >= 1 do
    if steps_a == steps_b and steps_a >= 2 do
      spanish_cousin(steps_a, g)
    else
      spanish_removed_label(steps_a, steps_b, g)
    end
  end

  defp spanish_cousin(steps, g) do
    degree = steps - 1
    base = if g == "female", do: "Prima", else: "Primo"
    ord = spanish_ordinal_suffix(degree, g)

    [base, ord]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp spanish_removed_label(steps_a, steps_b, g) do
    ordinal_n = min(steps_a, steps_b)
    removed = abs(steps_a - steps_b)
    direction = if steps_a < steps_b, do: :ascending, else: :descending

    base = spanish_base(direction, g)
    gen_suffix = spanish_generation_suffix(direction, removed, g)
    ord_suffix = spanish_ordinal_suffix(ordinal_n, g)

    [base, gen_suffix, ord_suffix]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  # --- Spanish helpers ---

  defp politico_suffix("male"), do: "político"
  defp politico_suffix("female"), do: "política"
  defp politico_suffix(_), do: "político/a"

  defp spanish_parent("male"), do: "Padre"
  defp spanish_parent("female"), do: "Madre"
  defp spanish_parent(_), do: "Padre/Madre"

  defp spanish_child("male"), do: "Hijo"
  defp spanish_child("female"), do: "Hija"
  defp spanish_child(_), do: "Hijo/a"

  defp spanish_hermano("male"), do: "Hermano"
  defp spanish_hermano("female"), do: "Hermana"
  defp spanish_hermano(_), do: "Hermano/a"

  defp spanish_abuelo("female"), do: "Abuela"
  defp spanish_abuelo(_), do: "Abuelo"

  defp spanish_bisabuelo("female"), do: "Bisabuela"
  defp spanish_bisabuelo(_), do: "Bisabuelo"

  defp spanish_tatarabuelo("female"), do: "Tatarabuela"
  defp spanish_tatarabuelo(_), do: "Tatarabuelo"

  defp spanish_trastatarabuelo("female"), do: "Trastatarabuela"
  defp spanish_trastatarabuelo(_), do: "Trastatarabuelo"

  defp spanish_nieto("female"), do: "Nieta"
  defp spanish_nieto(_), do: "Nieto"

  defp spanish_bisnieto("female"), do: "Bisnieta"
  defp spanish_bisnieto(_), do: "Bisnieto"

  defp spanish_tataranieto("female"), do: "Tataranieta"
  defp spanish_tataranieto(_), do: "Tataranieto"

  defp spanish_trastataranieto("female"), do: "Trastataranieta"
  defp spanish_trastataranieto(_), do: "Trastataranieto"

  defp spanish_base(:ascending, "male"), do: "Tío"
  defp spanish_base(:ascending, "female"), do: "Tía"
  defp spanish_base(:ascending, _), do: "Tío/a"
  defp spanish_base(:descending, "male"), do: "Sobrino"
  defp spanish_base(:descending, "female"), do: "Sobrina"
  defp spanish_base(:descending, _), do: "Sobrino/a"

  defp spanish_generation_suffix(_direction, 1, _g), do: ""
  defp spanish_generation_suffix(:ascending, 2, "female"), do: "abuela"
  defp spanish_generation_suffix(:ascending, 2, _), do: "abuelo"
  defp spanish_generation_suffix(:ascending, 3, "female"), do: "bisabuela"
  defp spanish_generation_suffix(:ascending, 3, _), do: "bisabuelo"
  defp spanish_generation_suffix(:ascending, 4, "female"), do: "tatarabuela"
  defp spanish_generation_suffix(:ascending, 4, _), do: "tatarabuelo"
  defp spanish_generation_suffix(:ascending, 5, "female"), do: "trastatarabuela"
  defp spanish_generation_suffix(:ascending, 5, _), do: "trastatarabuelo"
  defp spanish_generation_suffix(:ascending, n, "female") when n >= 6, do: "#{n}° abuela"
  defp spanish_generation_suffix(:ascending, n, _) when n >= 6, do: "#{n}° abuelo"
  defp spanish_generation_suffix(:descending, 2, "female"), do: "nieta"
  defp spanish_generation_suffix(:descending, 2, _), do: "nieto"
  defp spanish_generation_suffix(:descending, 3, "female"), do: "bisnieta"
  defp spanish_generation_suffix(:descending, 3, _), do: "bisnieto"
  defp spanish_generation_suffix(:descending, 4, "female"), do: "tataranieta"
  defp spanish_generation_suffix(:descending, 4, _), do: "tataranieto"
  defp spanish_generation_suffix(:descending, 5, "female"), do: "trastataranieta"
  defp spanish_generation_suffix(:descending, 5, _), do: "trastataranieto"
  defp spanish_generation_suffix(:descending, n, "female") when n >= 6, do: "#{n}° nieta"
  defp spanish_generation_suffix(:descending, n, _) when n >= 6, do: "#{n}° nieto"

  defp spanish_ordinal_suffix(1, _g), do: ""
  defp spanish_ordinal_suffix(2, "female"), do: "segunda"
  defp spanish_ordinal_suffix(2, _), do: "segundo"
  defp spanish_ordinal_suffix(3, "female"), do: "tercera"
  defp spanish_ordinal_suffix(3, _), do: "tercero"
  defp spanish_ordinal_suffix(4, "female"), do: "cuarta"
  defp spanish_ordinal_suffix(4, _), do: "cuarto"
  defp spanish_ordinal_suffix(5, "female"), do: "quinta"
  defp spanish_ordinal_suffix(5, _), do: "quinto"
  defp spanish_ordinal_suffix(6, "female"), do: "sexta"
  defp spanish_ordinal_suffix(6, _), do: "sexto"
  defp spanish_ordinal_suffix(7, "female"), do: "séptima"
  defp spanish_ordinal_suffix(7, _), do: "séptimo"
  defp spanish_ordinal_suffix(8, "female"), do: "octava"
  defp spanish_ordinal_suffix(8, _), do: "octavo"
  defp spanish_ordinal_suffix(n, _), do: "#{n}°"

  defp ordinal(1, g), do: t(g, "First")
  defp ordinal(2, g), do: t(g, "Second")
  defp ordinal(3, g), do: t(g, "Third")
  defp ordinal(4, g), do: t(g, "Fourth")
  defp ordinal(5, g), do: t(g, "Fifth")
  defp ordinal(6, g), do: t(g, "Sixth")
  defp ordinal(7, g), do: t(g, "Seventh")
  defp ordinal(8, g), do: t(g, "Eighth")
  defp ordinal(n, _g), do: "#{n}th"

  defp numeric_ordinal(1), do: "1st"
  defp numeric_ordinal(2), do: "2nd"
  defp numeric_ordinal(3), do: "3rd"
  defp numeric_ordinal(n) when rem(n, 10) == 1 and rem(n, 100) != 11, do: "#{n}st"
  defp numeric_ordinal(n) when rem(n, 10) == 2 and rem(n, 100) != 12, do: "#{n}nd"
  defp numeric_ordinal(n) when rem(n, 10) == 3 and rem(n, 100) != 13, do: "#{n}rd"
  defp numeric_ordinal(n), do: "#{n}th"
end
