defmodule Family.Galleries do
  import Ecto.Query
  alias Family.Repo
  alias Family.Galleries.Gallery
  alias Family.Galleries.Photo

  def list_galleries do
    Repo.all(from g in Gallery, order_by: [asc: g.inserted_at])
  end

  def get_gallery!(id), do: Repo.get!(Gallery, id)

  def create_gallery(attrs \\ %{}) do
    %Gallery{}
    |> Gallery.changeset(attrs)
    |> Repo.insert()
  end

  def change_gallery(%Gallery{} = gallery, attrs \\ %{}) do
    Gallery.changeset(gallery, attrs)
  end

  def delete_gallery(%Gallery{} = gallery) do
    Repo.delete(gallery)
  end

  def list_photos(gallery_id) do
    Repo.all(
      from p in Photo,
        where: p.gallery_id == ^gallery_id,
        order_by: [asc: p.inserted_at]
    )
  end

  def get_photo!(id), do: Repo.get!(Photo, id)

  def create_photo(attrs \\ %{}) do
    %Photo{}
    |> Photo.changeset(attrs)
    |> Repo.insert()
  end

  def delete_photo(%Photo{} = photo) do
    if photo.image, do: Family.Uploaders.Photo.delete({photo.image, photo})
    Repo.delete(photo)
  end

  def update_photo_processed(%Photo{} = photo, filename) do
    photo
    |> Photo.processed_changeset(%{image: filename, status: "processed"})
    |> Repo.update()
  end

  def update_photo_failed(%Photo{} = photo) do
    photo
    |> Ecto.Changeset.change(%{status: "failed"})
    |> Repo.update()
  end
end
