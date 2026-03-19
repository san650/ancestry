defmodule Ancestry.Galleries do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Galleries.Photo
  alias Ancestry.Galleries.PhotoPerson

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
        order_by: [asc: p.inserted_at, asc: p.id],
        preload: [:gallery]
    )
  end

  def get_photo!(id), do: Repo.get!(Photo, id) |> Repo.preload(:gallery)

  def create_photo(attrs \\ %{}) do
    with {:ok, photo} <- %Photo{} |> Photo.changeset(attrs) |> Repo.insert(),
         {:ok, _job} <- Oban.insert(Ancestry.Workers.ProcessPhotoJob.new(%{photo_id: photo.id})) do
      {:ok, Repo.preload(photo, :gallery)}
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
    |> case do
      {:ok, photo} -> {:ok, Repo.preload(photo, :gallery)}
      error -> error
    end
  end

  def update_photo_failed(%Photo{} = photo) do
    photo
    |> Ecto.Changeset.change(%{status: "failed"})
    |> Repo.update()
    |> case do
      {:ok, photo} -> {:ok, Repo.preload(photo, :gallery)}
      error -> error
    end
  end

  def tag_person_in_photo(photo_id, person_id, x, y) do
    %PhotoPerson{photo_id: photo_id, person_id: person_id}
    |> PhotoPerson.changeset(%{x: x, y: y})
    |> Repo.insert()
  end

  def untag_person_from_photo(photo_id, person_id) do
    from(pp in PhotoPerson,
      where: pp.photo_id == ^photo_id and pp.person_id == ^person_id
    )
    |> Repo.delete_all()

    :ok
  end

  def list_photo_people(photo_id) do
    Repo.all(
      from pp in PhotoPerson,
        where: pp.photo_id == ^photo_id,
        order_by: [asc: pp.inserted_at, asc: pp.id],
        preload: [:person]
    )
  end
end
