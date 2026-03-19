defmodule Ancestry.StringUtils do
  @doc """
  Strips diacritics and lowercases the string for accent-insensitive comparison.
  """
  def normalize(nil), do: ""
  def normalize(""), do: ""

  def normalize(string) do
    string
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end
end
