defmodule Ancestry.Commands.TagPersonInPhoto do
  @moduledoc """
  Command to tag a person in a photo. Coordinates `x` and `y` are
  optional — both must be present (and within `[0.0, 1.0]`) or both
  must be absent.
  """

  use Ancestry.Bus.Command

  alias Ancestry.Galleries.Photo

  @enforce_keys [:photo_id, :person_id]
  defstruct [:photo_id, :person_id, :x, :y]

  @types %{photo_id: :integer, person_id: :integer, x: :float, y: :float}
  @required [:photo_id, :person_id]

  @impl true
  def new(attrs) do
    cs =
      {%{}, @types}
      |> Ecto.Changeset.cast(attrs, Map.keys(@types))
      |> Ecto.Changeset.validate_required(@required)
      |> validate_coordinate_pair()
      |> validate_coordinate_range(:x)
      |> validate_coordinate_range(:y)

    if cs.valid?,
      do:
        {:ok, struct!(__MODULE__, Map.merge(%{x: nil, y: nil}, Ecto.Changeset.apply_changes(cs)))},
      else: {:error, %{cs | action: :validate}}
  end

  @impl true
  def new!(attrs), do: struct!(__MODULE__, Map.merge(%{x: nil, y: nil}, Map.new(attrs)))

  @impl true
  def handled_by, do: Ancestry.Handlers.TagPersonInPhotoHandler

  @impl true
  def primary_step, do: :photo_person

  @impl true
  def permission, do: {:update, Photo}

  defp validate_coordinate_pair(cs) do
    x = Ecto.Changeset.get_change(cs, :x)
    y = Ecto.Changeset.get_change(cs, :y)

    cond do
      is_nil(x) and is_nil(y) ->
        cs

      not is_nil(x) and not is_nil(y) ->
        cs

      true ->
        Ecto.Changeset.add_error(cs, :x, "x and y must be set together")
    end
  end

  defp validate_coordinate_range(cs, field) do
    case Ecto.Changeset.get_change(cs, field) do
      nil ->
        cs

      _ ->
        Ecto.Changeset.validate_number(cs, field,
          greater_than_or_equal_to: 0.0,
          less_than_or_equal_to: 1.0
        )
    end
  end
end
