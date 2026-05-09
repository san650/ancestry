defmodule Ancestry.Audit.SerializerTest do
  use ExUnit.Case, async: true

  alias Ancestry.Audit.Serializer

  defmodule SimpleCommand do
    use Ancestry.Bus.Command
    @enforce_keys [:photo_id, :text]
    defstruct [:photo_id, :text]
    @impl true
    def new(_), do: raise("n/a")
    @impl true
    def new!(a), do: struct!(__MODULE__, a)
    @impl true
    def handled_by, do: nil
    @impl true
    def primary_step, do: :primary
    @impl true
    def permission, do: {:test, SimpleCommand}
  end

  defmodule RedactedCommand do
    use Ancestry.Bus.Command
    @enforce_keys [:email, :password]
    defstruct [:email, :password]
    @impl true
    def new(_), do: raise("n/a")
    @impl true
    def new!(a), do: struct!(__MODULE__, a)
    @impl true
    def handled_by, do: nil
    @impl true
    def primary_step, do: :primary
    @impl true
    def permission, do: {:test, RedactedCommand}
    @impl true
    def redacted_fields, do: [:password]
  end

  defmodule BlobCommand do
    use Ancestry.Bus.Command
    @enforce_keys [:label, :photo]
    defstruct [:label, :photo]
    @impl true
    def new(_), do: raise("n/a")
    @impl true
    def new!(a), do: struct!(__MODULE__, a)
    @impl true
    def handled_by, do: nil
    @impl true
    def primary_step, do: :primary
    @impl true
    def permission, do: {:test, BlobCommand}
    @impl true
    def binary_fields, do: [:photo]
  end

  test "serializes a plain command into a map of its fields (no __struct__)" do
    cmd = SimpleCommand.new!(%{photo_id: 7, text: "hi"})
    assert Serializer.serialize(cmd) == %{photo_id: 7, text: "hi"}
  end

  test "redacts fields listed in redacted_fields/0" do
    cmd = RedactedCommand.new!(%{email: "a@b.c", password: "secret"})
    assert Serializer.serialize(cmd) == %{email: "a@b.c", password: "[redacted]"}
  end

  test "replaces fields listed in binary_fields/0 with the binary-blob marker" do
    cmd = BlobCommand.new!(%{label: "x", photo: <<1, 2, 3>>})
    assert Serializer.serialize(cmd) == %{label: "x", photo: "binary-blob"}
  end
end
