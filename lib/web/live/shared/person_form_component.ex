defmodule Web.Shared.PersonFormComponent do
  use Web, :html

  embed_templates "person_form_component.html"

  defp living_checked?(form) do
    val = form[:deceased].value
    !(val in ["true", true])
  end

  defp month_options do
    [
      {gettext("Jan"), "1"},
      {gettext("Feb"), "2"},
      {gettext("Mar"), "3"},
      {gettext("Apr"), "4"},
      {gettext("May"), "5"},
      {gettext("Jun"), "6"},
      {gettext("Jul"), "7"},
      {gettext("Aug"), "8"},
      {gettext("Sep"), "9"},
      {gettext("Oct"), "10"},
      {gettext("Nov"), "11"},
      {gettext("Dec"), "12"}
    ]
  end

  defp day_options do
    Enum.map(1..31, fn d -> {to_string(d), to_string(d)} end)
  end

  defp upload_error_to_string(:too_large), do: gettext("File too large (max 20MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("File type not supported")
  defp upload_error_to_string(:too_many_files), do: gettext("Too many files (max 1)")
  defp upload_error_to_string(err), do: gettext("Upload error: %{error}", error: inspect(err))
end
