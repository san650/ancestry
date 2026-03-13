defmodule Ancestry.Uploaders.FamilyCover do
  use Waffle.Definition

  @versions [:cover]
  @valid_extensions ~w(.jpg .jpeg .png .webp)

  def validate({file, _}) do
    file.file_name
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @valid_extensions))
  end

  def transform(:cover, _) do
    {:convert, "-resize 1200x800> -auto-orient -strip -quality 85", :jpg}
  end

  def filename(:cover, _), do: "cover"

  def storage_dir(_version, {_file, scope}) do
    "uploads/families/#{scope.id}"
  end
end
