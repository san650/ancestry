defmodule Web.Shared.PersonFormComponent do
  use Web, :html

  embed_templates "person_form_component.html"

  defp living_checked?(form) do
    val = form[:deceased].value
    !(val in ["true", true])
  end

  defp month_options do
    [
      {"Jan", "1"},
      {"Feb", "2"},
      {"Mar", "3"},
      {"Apr", "4"},
      {"May", "5"},
      {"Jun", "6"},
      {"Jul", "7"},
      {"Aug", "8"},
      {"Sep", "9"},
      {"Oct", "10"},
      {"Nov", "11"},
      {"Dec", "12"}
    ]
  end

  defp day_options do
    Enum.map(1..31, fn d -> {to_string(d), to_string(d)} end)
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 20MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not supported"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
