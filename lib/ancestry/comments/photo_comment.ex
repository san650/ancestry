defmodule Ancestry.Comments.PhotoComment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photo_comments" do
    field :text, :string
    belongs_to :photo, Ancestry.Galleries.Photo
    belongs_to :account, Ancestry.Identity.Account

    timestamps()
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:text])
    |> validate_required([:text])
    |> validate_length(:text, max: 5000)
    |> foreign_key_constraint(:photo_id)
  end
end
