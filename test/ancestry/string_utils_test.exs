defmodule Ancestry.StringUtilsTest do
  use ExUnit.Case, async: true

  alias Ancestry.StringUtils

  describe "normalize/1" do
    test "strips diacritics and lowercases" do
      assert StringUtils.normalize("María") == "maria"
      assert StringUtils.normalize("José") == "jose"
      assert StringUtils.normalize("González") == "gonzalez"
    end

    test "handles plain ASCII" do
      assert StringUtils.normalize("John") == "john"
    end

    test "handles empty string" do
      assert StringUtils.normalize("") == ""
    end

    test "handles multiple diacritics" do
      assert StringUtils.normalize("Ñoño") == "nono"
    end

    test "handles umlauts and other marks" do
      assert StringUtils.normalize("Müller") == "muller"
      assert StringUtils.normalize("Björk") == "bjork"
      assert StringUtils.normalize("François") == "francois"
    end
  end
end
