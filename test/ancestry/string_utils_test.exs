defmodule Ancestry.StringUtilsTest do
  use ExUnit.Case, async: true

  alias Ancestry.StringUtils

  describe "normalize/1" do
    test "returns empty string for nil" do
      assert StringUtils.normalize(nil) == ""
    end

    test "strips diacritics and lowercases" do
      assert StringUtils.normalize("Martín") == "martin"
    end

    test "returns empty string for empty string" do
      assert StringUtils.normalize("") == ""
    end

    test "handles plain ASCII" do
      assert StringUtils.normalize("John") == "john"
    end

    test "handles multiple diacritics" do
      assert StringUtils.normalize("Ñoño") == "nono"
    end

    test "handles umlauts and other marks" do
      assert StringUtils.normalize("Müller") == "muller"
      assert StringUtils.normalize("Björk") == "bjork"
      assert StringUtils.normalize("François") == "francois"
    end

    test "handles more accented names" do
      assert StringUtils.normalize("María") == "maria"
      assert StringUtils.normalize("José") == "jose"
      assert StringUtils.normalize("González") == "gonzalez"
    end
  end

  describe "normalize_sql_search/1" do
    test "normalizes, escapes, and wraps in wildcards" do
      assert StringUtils.normalize_sql_search("Martín") == "%martin%"
    end

    test "escapes SQL wildcards" do
      assert StringUtils.normalize_sql_search("100%") == "%100\\%%"
    end

    test "escapes underscores" do
      assert StringUtils.normalize_sql_search("a_b") == "%a\\_b%"
    end

    test "escapes backslashes" do
      assert StringUtils.normalize_sql_search("a\\b") == "%a\\\\b%"
    end

    test "handles nil" do
      assert StringUtils.normalize_sql_search(nil) == "%%"
    end

    test "handles cross-field query with diacritics" do
      assert StringUtils.normalize_sql_search("martín v") == "%martin v%"
    end
  end
end
