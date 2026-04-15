defmodule Ancestry.AvatarsTest do
  use ExUnit.Case, async: true

  alias Ancestry.Avatars
  alias Ancestry.Identity.Account

  describe "initials/1" do
    test "full name returns first and last initials" do
      assert Avatars.initials(%Account{name: "Santiago Ferreira", email: "sf@example.com"}) ==
               "SF"
    end

    test "single-word name returns one initial" do
      assert Avatars.initials(%Account{name: "Santiago", email: "s@example.com"}) == "S"
    end

    test "nil name falls back to email prefix" do
      assert Avatars.initials(%Account{name: nil, email: "maria@example.com"}) == "M"
    end

    test "empty name falls back to email prefix" do
      assert Avatars.initials(%Account{name: "", email: "maria@example.com"}) == "M"
    end

    test "nil account returns ?" do
      assert Avatars.initials(nil) == "?"
    end

    test "three-word name uses first and last" do
      assert Avatars.initials(%Account{name: "Ana María López", email: "a@example.com"}) == "AL"
    end
  end

  describe "color/1" do
    test "returns consistent color for same ID" do
      assert Avatars.color(42) == Avatars.color(42)
    end

    test "returns a hex color string" do
      assert Avatars.color(1) =~ ~r/^#[0-9a-fA-F]{6}$/
    end

    test "nil returns default gray" do
      assert Avatars.color(nil) == "#6b7280"
    end

    test "stays within palette for various IDs" do
      for id <- 1..50 do
        color = Avatars.color(id)
        assert color in Avatars.palette(), "ID #{id} produced #{color} not in palette"
      end
    end
  end
end
