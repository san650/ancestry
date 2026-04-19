defmodule Ancestry.Kinship.Label do
  @moduledoc """
  Produces human-readable kinship labels based on a coordinate system
  (steps_a, steps_b), a half-relationship flag, and person gender.

  The label describes "what person A is to person B."

  Uses `Gettext.pgettext/4` with gender as the message context so translations
  can be gender-specific. In the default English locale, pgettext returns the
  msgid unchanged.
  """

  @doc """
  Formats a kinship label given the generational coordinates, half flag, and gender.

  ## Parameters

  - `steps_a` — steps from person A to the MRCA
  - `steps_b` — steps from person B to the MRCA
  - `half?` — whether this is a half-relationship
  - `gender` — person A's gender: "male", "female", or anything else treated as "other"
  """
  def format(steps_a, steps_b, half?, gender) do
    g = normalize_gender(gender)
    classify(steps_a, steps_b, half?, g)
  end

  defp normalize_gender("male"), do: "male"
  defp normalize_gender("female"), do: "female"
  defp normalize_gender(_), do: "other"

  defp t(g, msgid), do: Gettext.pgettext(Web.Gettext, g, msgid)
  defp t(g, msgid, bindings), do: Gettext.pgettext(Web.Gettext, g, msgid, bindings)

  # Direct line ascending (person A is the MRCA)
  defp classify(0, 1, _half?, g), do: t(g, "Parent")
  defp classify(0, 2, _half?, g), do: t(g, "Grandparent")

  defp classify(0, steps_b, _half?, g) when steps_b >= 3 do
    ancestor_label(steps_b, g)
  end

  # Direct line descending (person B is the MRCA)
  defp classify(1, 0, _half?, g), do: t(g, "Child")
  defp classify(2, 0, _half?, g), do: t(g, "Grandchild")

  defp classify(steps_a, 0, _half?, g) when steps_a >= 3 do
    descendant_label(steps_a, g)
  end

  # Siblings
  defp classify(1, 1, true, g), do: t(g, "Half-Sibling")
  defp classify(1, 1, false, g), do: t(g, "Sibling")

  # Uncle & Aunt chain (steps_a == 1, steps_b >= 2)
  defp classify(1, 2, _half?, g), do: t(g, "Uncle & Aunt")
  defp classify(1, 3, _half?, g), do: t(g, "Great Uncle & Aunt")
  defp classify(1, 4, _half?, g), do: t(g, "Great Grand Uncle & Aunt")

  defp classify(1, steps_b, _half?, g) when steps_b >= 5 do
    t(g, "%{nth} Great Grand Uncle & Aunt", nth: numeric_ordinal(steps_b - 4))
  end

  # Nephew & Niece chain (steps_b == 1, steps_a >= 2)
  defp classify(2, 1, _half?, g), do: t(g, "Nephew & Niece")
  defp classify(3, 1, _half?, g), do: t(g, "Grand Nephew & Niece")
  defp classify(4, 1, _half?, g), do: t(g, "Great Grand Nephew & Niece")

  defp classify(steps_a, 1, _half?, g) when steps_a >= 5 do
    t(g, "%{nth} Great Grand Nephew & Niece", nth: numeric_ordinal(steps_a - 4))
  end

  # Cousins (catch-all: both steps_a >= 2 and steps_b >= 2)
  defp classify(steps_a, steps_b, half?, g) do
    half_prefix = if half?, do: t(g, "Half-"), else: ""

    cousin_str =
      if steps_a == steps_b do
        same_gen_cousin_label(steps_a, g)
      else
        removed_cousin_label(steps_a, steps_b, g)
      end

    "#{half_prefix}#{cousin_str}"
  end

  # Same-generation cousins
  defp same_gen_cousin_label(steps, g) do
    degree = steps - 1
    degree_str = ordinal(degree, g)
    t(g, "%{degree} Cousin", degree: degree_str)
  end

  # Removed cousins — direction-aware for Spanish, English otherwise
  defp removed_cousin_label(steps_a, steps_b, g) do
    locale = Gettext.get_locale(Web.Gettext)

    if String.starts_with?(locale, "es") do
      spanish_removed_cousin_label(steps_a, steps_b, g)
    else
      english_removed_cousin_label(steps_a, steps_b, g)
    end
  end

  defp english_removed_cousin_label(steps_a, steps_b, g) do
    degree = min(steps_a, steps_b) - 1
    removed = abs(steps_a - steps_b)
    degree_str = ordinal(degree, g)

    removed_str =
      cond do
        removed == 1 -> t(g, ", Once Removed")
        removed == 2 -> t(g, ", Twice Removed")
        true -> t(g, ", %{count} Times Removed", count: removed)
      end

    t(g, "%{degree} Cousin%{removed}", degree: degree_str, removed: removed_str)
  end

  defp spanish_removed_cousin_label(steps_a, steps_b, g) do
    ordinal_n = min(steps_a, steps_b)
    removed = abs(steps_a - steps_b)
    direction = if steps_a < steps_b, do: :ascending, else: :descending

    base = spanish_base(direction, g)
    gen_suffix = spanish_generation_suffix(direction, removed)
    ord_suffix = spanish_ordinal_suffix(ordinal_n, g)

    [base, gen_suffix, ord_suffix]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp spanish_base(:ascending, "male"), do: "Tío"
  defp spanish_base(:ascending, "female"), do: "Tía"
  defp spanish_base(:ascending, _), do: "Tío/a"
  defp spanish_base(:descending, "male"), do: "Sobrino"
  defp spanish_base(:descending, "female"), do: "Sobrina"
  defp spanish_base(:descending, _), do: "Sobrino/a"

  defp spanish_generation_suffix(_direction, 1), do: ""
  defp spanish_generation_suffix(:ascending, 2), do: "abuelo/abuela"
  defp spanish_generation_suffix(:ascending, 3), do: "bisabuelo/bisabuela"
  defp spanish_generation_suffix(:ascending, 4), do: "tatarabuelo/tatarabuela"
  defp spanish_generation_suffix(:ascending, 5), do: "trastatarabuelo/trastatarabuela"

  defp spanish_generation_suffix(:ascending, n) when n >= 6,
    do: "#{n}° abuelo/abuela"

  defp spanish_generation_suffix(:descending, 2), do: "nieto/nieta"
  defp spanish_generation_suffix(:descending, 3), do: "bisnieto/bisnieta"
  defp spanish_generation_suffix(:descending, 4), do: "tataranieto/tataranieta"
  defp spanish_generation_suffix(:descending, 5), do: "trastataranieto/trastataranieta"

  defp spanish_generation_suffix(:descending, n) when n >= 6,
    do: "#{n}° nieto/nieta"

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

  defp ancestor_label(steps, g) do
    greats = steps - 2

    cond do
      greats == 1 -> t(g, "Great Grandparent")
      greats == 2 -> t(g, "Great Great Grandparent")
      greats >= 3 -> t(g, "%{nth} Great Grandparent", nth: numeric_ordinal(greats))
    end
  end

  defp descendant_label(steps, g) do
    greats = steps - 2

    cond do
      greats == 1 -> t(g, "Great Grandchild")
      greats == 2 -> t(g, "Great Great Grandchild")
      greats >= 3 -> t(g, "%{nth} Great Grandchild", nth: numeric_ordinal(greats))
    end
  end

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
