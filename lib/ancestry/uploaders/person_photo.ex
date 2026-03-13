defmodule Ancestry.Uploaders.PersonPhoto do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original]

  def validate({file, _}) do
    file.file_name
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in ~w(.jpg .jpeg .png .webp)))
  end

  def filename(:original, _), do: "photo"

  def storage_dir(_version, {_file, scope}) do
    "uploads/persons/#{scope.id}"
  end
end
