defmodule Ancestry.Avatars do
  @moduledoc "Pure functions for generating user avatar initials and colors."

  alias Ancestry.Identity.Account

  @palette [
    "#6366f1",
    "#f59e0b",
    "#10b981",
    "#ef4444",
    "#8b5cf6",
    "#ec4899",
    "#14b8a6",
    "#f97316",
    "#06b6d4",
    "#84cc16",
    "#e11d48",
    "#0ea5e9"
  ]

  def palette, do: @palette

  @spec initials(Account.t() | nil) :: String.t()
  def initials(nil), do: "?"

  def initials(%Account{name: name, email: email}) do
    case normalize_name(name) do
      nil -> email_initial(email)
      name -> name_initials(name)
    end
  end

  @spec color(integer() | nil) :: String.t()
  def color(nil), do: "#6b7280"

  def color(account_id) when is_integer(account_id) do
    Enum.at(@palette, rem(account_id, length(@palette)))
  end

  defp normalize_name(nil), do: nil

  defp normalize_name(name) when is_binary(name) do
    trimmed = String.trim(name)
    if trimmed == "", do: nil, else: trimmed
  end

  defp name_initials(name) do
    words = String.split(name)

    case words do
      [single] ->
        single |> String.first() |> String.upcase()

      [first | rest] ->
        last = List.last(rest)
        (String.first(first) <> String.first(last)) |> String.upcase()
    end
  end

  defp email_initial(nil), do: "?"

  defp email_initial(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first("")
    |> String.first()
    |> case do
      nil -> "?"
      char -> String.upcase(char)
    end
  end
end
