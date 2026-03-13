defmodule Ancestry.Uploaders.PersonPhoto do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original, :thumbnail]
  @valid_extensions ~w(.jpg .jpeg .png .webp .tif .tiff)

  def validate({file, _}) do
    file.file_name
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @valid_extensions))
  end

  def transform(:original, _), do: :noaction

  def transform(:thumbnail, _) do
    {:convert, "-resize 400x400> -auto-orient -strip", :jpg}
  end

  def filename(:original, _), do: "photo"
  def filename(:thumbnail, _), do: "thumbnail"

  def storage_dir(_version, {_file, scope}) do
    "uploads/people/#{scope.id}"
  end
end
