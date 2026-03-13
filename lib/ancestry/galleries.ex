defmodule Ancestry.Galleries do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Galleries.Photo

  # TODO: Remove once GalleryLive.Index is updated to pass family_id (Task 10)
  def list_galleries do
    Repo.all(from g in Gallery, order_by: [asc: g.inserted_at])
  end

  def list_galleries(family_id) do
    Repo.all(from g in Gallery, where: g.family_id == ^family_id, order_by: [asc: g.inserted_at])
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
        order_by: [asc: p.inserted_at, asc: p.id]
    )
  end

  def get_photo!(id), do: Repo.get!(Photo, id)

  def create_photo(attrs \\ %{}) do
    with {:ok, photo} <- %Photo{} |> Photo.changeset(attrs) |> Repo.insert(),
         {:ok, _job} <- Oban.insert(Ancestry.Workers.ProcessPhotoJob.new(%{photo_id: photo.id})) do
      {:ok, photo}
    end
  end

  def delete_photo(%Photo{} = photo) do
    if photo.image, do: Ancestry.Uploaders.Photo.delete({photo.image, photo})
    Repo.delete(photo)
  end

  def update_photo_processed(%Photo{} = photo, filename) do
    photo
    |> Ecto.Changeset.change(image: %{file_name: filename, updated_at: nil}, status: "processed")
    |> Repo.update()
  end

  def update_photo_failed(%Photo{} = photo) do
    photo
    |> Ecto.Changeset.change(%{status: "failed"})
    |> Repo.update()
  end
end
