defmodule Web.Plugs.Locale do
  @moduledoc "Sets Gettext locale from account, session, or Accept-Language header."
  import Plug.Conn

  @supported_locales ~w(en-US es-UY)
  @default_locale "en-US"

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = detect_locale(conn)
    Gettext.put_locale(Web.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_session("locale", locale)
  end

  defp detect_locale(conn) do
    from_account(conn) || from_session(conn) || from_accept_language(conn) || @default_locale
  end

  defp from_account(%{assigns: %{current_scope: %{account: %{locale: locale}}}})
       when is_binary(locale) and locale != "" do
    if locale in @supported_locales, do: locale
  end

  defp from_account(_conn), do: nil

  defp from_session(conn) do
    locale = get_session(conn, "locale")
    if locale in @supported_locales, do: locale
  end

  defp from_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [header | _] -> parse_accept_language(header)
      _ -> nil
    end
  end

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_language_tag/1)
    |> Enum.sort_by(fn {_lang, q} -> q end, :desc)
    |> Enum.find_value(fn {lang, _q} -> match_locale(lang) end)
  end

  defp parse_language_tag(tag) do
    case String.split(String.trim(tag), ";") do
      [lang] ->
        {String.trim(lang), 1.0}

      [lang, quality] ->
        q =
          case Regex.run(~r/q=([\d.]+)/, quality) do
            [_, val] ->
              String.to_float(if String.contains?(val, "."), do: val, else: val <> ".0")

            _ ->
              1.0
          end

        {String.trim(lang), q}
    end
  end

  defp match_locale(lang) do
    downcased = String.downcase(lang)

    cond do
      downcased == "es-uy" -> "es-UY"
      String.starts_with?(downcased, "es") -> "es-UY"
      downcased == "en-us" -> "en-US"
      String.starts_with?(downcased, "en") -> "en-US"
      true -> nil
    end
  end
end
