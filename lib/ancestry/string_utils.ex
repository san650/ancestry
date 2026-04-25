defmodule Ancestry.StringUtils do
  @doc """
  Strips diacritics and lowercases the string for accent-insensitive comparison.
  """
  def normalize(nil), do: ""
  def normalize(""), do: ""

  def normalize(string) when is_binary(string) do
    string
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end

  @doc """
  Normalizes a search term and wraps it in SQL `LIKE` wildcards (`%...%`),
  escaping any literal `%`, `_`, and `\\` characters in the input.
  """
  def normalize_sql_search(term) do
    escaped =
      term
      |> normalize()
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%#{escaped}%"
  end
end
