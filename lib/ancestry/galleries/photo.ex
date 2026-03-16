defmodule Ancestry.Galleries.Photo do
  use Ecto.Schema
  use Waffle.Ecto.Schema
  import Ecto.Changeset

  schema "photos" do
    field :image, Ancestry.Uploaders.Photo.Type
    field :original_path, :string
    field :original_filename, :string
    field :content_type, :string
    field :status, :string, default: "pending"
    belongs_to :gallery, Ancestry.Galleries.Gallery
    has_many :photo_comments, Ancestry.Comments.PhotoComment
    timestamps(updated_at: false)
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:gallery_id, :original_path, :original_filename, :content_type, :status])
    |> validate_required([:gallery_id, :original_path, :original_filename, :content_type])
    |> foreign_key_constraint(:gallery_id)
  end

  def processed_changeset(photo, attrs) do
    photo
    |> cast_attachments(attrs, [:image])
    |> cast(attrs, [:status])
  end
end
