defmodule Ancestry.Import.CSV.FamilyEcho do
  @moduledoc """
  CSV adapter for FamilyEcho exports.

  Parses person data and relationship references from the FamilyEcho CSV format.
  """

  @behaviour Ancestry.Import.CSV.Adapter

  @prefix "family_echo_"

  @impl true
  def parse_person(row) do
    given = blank_to_nil(row["Given names"])
    surname = blank_to_nil(row["Surname now"])

    if is_nil(given) and is_nil(surname) do
      {:skip, "no name"}
    else
      {:ok,
       %{
         external_id: @prefix <> row["ID"],
         given_name: given,
         surname: surname,
         surname_at_birth: blank_to_nil(row["Surname at birth"]),
         nickname: blank_to_nil(row["Nickname"]),
         title: blank_to_nil(row["Title"]),
         suffix: blank_to_nil(row["Suffix"]),
         gender: parse_gender(row["Gender"]),
         living: parse_living(row["Deceased"]),
         birth_year: parse_integer(row["Birth year"]),
         birth_month: parse_integer(row["Birth month"]),
         birth_day: parse_integer(row["Birth day"]),
         death_year: parse_integer(row["Death year"]),
         death_month: parse_integer(row["Death month"]),
         death_day: parse_integer(row["Death day"])
       }}
    end
  end

  @impl true
  def parse_relationships(row) do
    person_eid = @prefix <> row["ID"]

    parents =
      [
        parse_parent(row["Mother ID"], person_eid, "mother"),
        parse_parent(row["Father ID"], person_eid, "father")
      ]
      |> Enum.reject(&is_nil/1)

    partner =
      case blank_to_nil(row["Partner ID"]) do
        nil -> []
        partner_id -> [{:partner, person_eid, @prefix <> partner_id, %{}}]
      end

    ex_partners =
      case blank_to_nil(row["Ex-partner IDs"]) do
        nil ->
          []

        ids_string ->
          ids_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(fn ex_id -> {:ex_partner, person_eid, @prefix <> ex_id, %{}} end)
      end

    parents ++ partner ++ ex_partners
  end

  defp parse_parent(id_value, person_eid, role) do
    case blank_to_nil(id_value) do
      nil -> nil
      parent_id -> {:parent, @prefix <> parent_id, person_eid, %{role: role}}
    end
  end

  defp parse_gender("Female"), do: "female"
  defp parse_gender("Male"), do: "male"
  defp parse_gender(value) when value in ["", nil], do: nil
  defp parse_gender(_other), do: "other"

  defp parse_living("Y"), do: "no"
  defp parse_living(_), do: "yes"

  defp parse_integer(nil), do: nil

  defp parse_integer(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.to_integer(trimmed)
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
