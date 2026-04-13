defmodule Web.Gettext.Plural do
  @moduledoc """
  Custom plural forms module that maps regional locale codes (e.g. "en-US",
  "es-UY") to their base language for CLDR plural-rule lookup.

  Gettext's built-in `Gettext.Plural` only knows base CLDR locales like "en"
  and "es". This module delegates to `Gettext.Plural` after stripping the
  region subtag so that locales such as "en-US" and "es-UY" resolve correctly.
  """

  @behaviour Gettext.Plural

  @impl Gettext.Plural
  def init(%{locale: locale} = context) do
    base = locale |> String.split("-") |> hd()
    Gettext.Plural.init(%{context | locale: base})
  end

  @impl Gettext.Plural
  def nplurals(plural_info) do
    Gettext.Plural.nplurals(plural_info)
  end

  @impl Gettext.Plural
  def plural(plural_info, n) do
    Gettext.Plural.plural(plural_info, n)
  end
end
