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

  def change_gallery(%Gallery{} = gallery, attrs \\ %{}) do
    Gallery.changeset(gallery, attrs)
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

  def photo_exists_in_gallery?(gallery_id, file_hash) do
    Repo.exists?(
      from p in Photo,
        where: p.gallery_id == ^gallery_id and p.file_hash == ^file_hash
    )
  end

  def list_photo_people(photo_id) do
    Repo.all(
      from pp in PhotoPerson,
        where: pp.photo_id == ^photo_id,
        order_by: [asc: pp.inserted_at, asc: pp.id],
        preload: [:person]
    )
  end

  def list_photos_for_person(person_id) do
    Repo.all(
      from p in Photo,
        join: pp in PhotoPerson,
        on: pp.photo_id == p.id,
        where: pp.person_id == ^person_id and p.status == "processed",
        order_by: [desc: p.inserted_at, desc: p.id],
        preload: [:gallery]
    )
  end
end
