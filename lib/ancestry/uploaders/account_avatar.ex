defmodule Ancestry.Uploaders.AccountAvatar do
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
    {:convert, "-resize 150x150^ -gravity center -extent 150x150 -auto-orient -strip", :jpg}
  end

  def filename(:original, _), do: "avatar"
  def filename(:thumbnail, _), do: "thumbnail"

  def storage_dir(_version, {_file, scope}) do
    "uploads/accounts/#{scope.id}/avatar"
  end
end
