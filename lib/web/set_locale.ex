defmodule Web.SetLocale do
  @moduledoc "LiveView on_mount hook that sets Gettext locale from account or session."

  @default_locale "en-US"

  def on_mount(:default, _params, session, socket) do
    locale = detect_locale(socket, session)
    Gettext.put_locale(Web.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  defp detect_locale(socket, session) do
    from_account(socket) || from_session(session) || @default_locale
  end

  defp from_account(%{assigns: %{current_scope: %{account: %{locale: locale}}}})
       when is_binary(locale) and locale != "" do
    locale
  end

  defp from_account(_socket), do: nil

  defp from_session(session), do: session["locale"]
end
