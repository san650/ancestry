defmodule Ancestry.Uploaders.Photo do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original, :large, :thumbnail]

  @valid_extensions ~w(.jpg .jpeg .png .webp .gif .dng .nef .tiff .tif)

  def versions, do: @versions

  def validate({file, _}) do
    file.file_name
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @valid_extensions))
  end

  # Keep the original as-is; large and thumbnail are always output as JPEG
  def transform(:original, _), do: :noaction

  def transform(:large, _) do
    {:convert, "-resize 1920x1920> -auto-orient -strip", :jpg}
  end

  def transform(:thumbnail, _) do
    {:convert, "-resize 400x400> -auto-orient -strip", :jpg}
  end

  # Original keeps its extension; processed versions are always .jpg
  def filename(:original, {file, _}) do
    "original#{Path.extname(file.file_name) |> String.downcase()}"
  end

  def filename(version, _), do: "#{version}.jpg"

  # Files stored at priv/static/uploads/photos/{family_id}/{gallery_id}/{photo_id}/
  def storage_dir(_version, {_file, scope}) do
    "uploads/photos/#{scope.gallery.family_id}/#{scope.gallery_id}/#{scope.id}"
  end
end
