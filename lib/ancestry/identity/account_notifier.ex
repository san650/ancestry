defmodule Ancestry.Identity.AccountNotifier do
  import Swoosh.Email
  use Gettext, backend: Web.Gettext

  alias Ancestry.Mailer
  alias Ancestry.Identity.Account

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Ancestry", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a account email.
  """
  def deliver_update_email_instructions(account, url) do
    locale = account.locale || "en-US"

    Gettext.with_locale(Web.Gettext, locale, fn ->
      deliver(account.email, gettext("Update email instructions"), """

      ==============================

      #{gettext("Hi %{email},", email: account.email)}

      #{gettext("You can change your email by visiting the URL below:")}

      #{url}

      #{gettext("If you didn't request this change, please ignore this.")}

      ==============================
      """)
    end)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(account, url) do
    case account do
      %Account{confirmed_at: nil} -> deliver_confirmation_instructions(account, url)
      _ -> deliver_magic_link_instructions(account, url)
    end
  end

  defp deliver_magic_link_instructions(account, url) do
    locale = account.locale || "en-US"

    Gettext.with_locale(Web.Gettext, locale, fn ->
      deliver(account.email, gettext("Log in instructions"), """

      ==============================

      #{gettext("Hi %{email},", email: account.email)}

      #{gettext("You can log into your account by visiting the URL below:")}

      #{url}

      #{gettext("If you didn't request this email, please ignore this.")}

      ==============================
      """)
    end)
  end

  defp deliver_confirmation_instructions(account, url) do
    locale = account.locale || "en-US"

    Gettext.with_locale(Web.Gettext, locale, fn ->
      deliver(account.email, gettext("Confirmation instructions"), """

      ==============================

      #{gettext("Hi %{email},", email: account.email)}

      #{gettext("You can confirm your account by visiting the URL below:")}

      #{url}

      #{gettext("If you didn't create an account with us, please ignore this.")}

      ==============================
      """)
    end)
  end
end
