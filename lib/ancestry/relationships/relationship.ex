defmodule Ancestry.Relationships.Relationship do
  use Ecto.Schema
  import Ecto.Changeset
  import PolymorphicEmbed

  schema "relationships" do
    field :person_a_id, :integer
    field :person_b_id, :integer
    field :type, :string

    polymorphic_embeds_one(:metadata,
      types: [
        parent: Ancestry.Relationships.Metadata.ParentMetadata,
        partner: Ancestry.Relationships.Metadata.PartnerMetadata,
        ex_partner: Ancestry.Relationships.Metadata.ExPartnerMetadata
      ],
      type_field_name: :__type__,
      on_type_not_found: :raise,
      on_replace: :update
    )

    timestamps()
  end

  @valid_types ~w(parent partner ex_partner)

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:person_a_id, :person_b_id, :type])
    |> validate_required([:person_a_id, :person_b_id, :type])
    |> validate_inclusion(:type, @valid_types)
    |> validate_different_persons()
    |> maybe_order_symmetric_ids()
    |> cast_polymorphic_embed(:metadata, required: false)
    |> unique_constraint([:person_a_id, :person_b_id, :type],
      name: :relationships_person_a_id_person_b_id_type_index,
      message: "relationship already exists"
    )
  end

  defp validate_different_persons(changeset) do
    a = get_field(changeset, :person_a_id)
    b = get_field(changeset, :person_b_id)

    if a && b && a == b do
      add_error(changeset, :person_b_id, "cannot be the same person")
    else
      changeset
    end
  end

  defp maybe_order_symmetric_ids(changeset) do
    type = get_field(changeset, :type)
    a = get_field(changeset, :person_a_id)
    b = get_field(changeset, :person_b_id)

    if type in ~w(partner ex_partner) && a && b && a > b do
      changeset
      |> put_change(:person_a_id, b)
      |> put_change(:person_b_id, a)
    else
      changeset
    end
  end
end
