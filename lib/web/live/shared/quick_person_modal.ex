defmodule Web.Shared.QuickPersonModal do
  use Web, :live_component

  alias Ancestry.Families
  alias Ancestry.Organizations
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:form, to_form(People.change_person(%Person{}), as: :person))
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:show_acquaintance, fn -> true end)
      |> assign_new(:show_modal_wrapper, fn -> true end)
      |> assign_new(:family_id, fn -> nil end)
      |> assign_new(:prefill_name, fn -> nil end)

    socket =
      if socket.assigns[:prefill_applied] != true && socket.assigns.prefill_name do
        changeset =
          People.change_person(%Person{}, %{"given_name" => socket.assigns.prefill_name})

        socket
        |> assign(:form, to_form(changeset, as: :person))
        |> assign(:prefill_applied, true)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    if assigns.show_modal_wrapper do
      ~H"""
      <div>
        <div
          id={@id}
          class="fixed inset-0 z-50 flex items-end lg:items-center justify-center"
          phx-window-keydown="cancel"
          phx-key="Escape"
          phx-target={@myself}
        >
          <div
            class="absolute inset-0 bg-cm-black/60 backdrop-blur-sm"
            phx-click="cancel"
            phx-target={@myself}
          >
          </div>
          <div
            class="relative bg-cm-white border-2 border-cm-black w-full max-w-none lg:max-w-lg mx-0 lg:mx-4 rounded-cm p-8 max-h-[90vh] overflow-y-auto"
            role="dialog"
            aria-modal="true"
            aria-labelledby={"#{@id}-title"}
            phx-mounted={JS.focus_first()}
          >
            <h2
              id={"#{@id}-title"}
              class="font-cm-display text-xl text-cm-indigo uppercase tracking-wider mb-6"
            >
              {gettext("New Person")}
            </h2>
            {render_form(assigns)}
          </div>
        </div>
      </div>
      """
    else
      ~H"""
      <div id={@id}>
        {render_form(assigns)}
      </div>
      """
    end
  end

  defp render_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id={"#{@id}-form"}
      phx-target={@myself}
      phx-change="validate"
      phx-submit="save"
      multipart
      class="space-y-4"
    >
      <%!-- Photo upload --%>
      <div>
        <label class="font-cm-mono text-[10px] uppercase tracking-wider text-cm-text-muted">
          {gettext("Photo")}
        </label>
        <div class="mt-1">
          <%= if @uploads.photo.entries == [] do %>
            <label
              class="flex items-center justify-center w-20 h-20 rounded-full border-2 border-dashed border-cm-black/30 cursor-pointer hover:border-cm-black transition-colors"
              {test_id("quick-person-photo-placeholder")}
            >
              <.icon name="hero-camera" class="w-6 h-6 text-cm-text-muted/40" />
              <.live_file_input upload={@uploads.photo} class="sr-only" />
            </label>
          <% else %>
            <%= for entry <- @uploads.photo.entries do %>
              <div class="flex items-center gap-3">
                <.live_img_preview entry={entry} class="w-20 h-20 rounded-full object-cover" />
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-cm-body font-medium text-cm-black truncate">
                    {entry.client_name}
                  </p>
                  <div class="mt-1 h-1.5 bg-cm-surface rounded-full overflow-hidden">
                    <div
                      class="h-full bg-cm-indigo rounded-full transition-all duration-300"
                      style={"width: #{entry.progress}%"}
                    >
                    </div>
                  </div>
                </div>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  phx-target={@myself}
                  class="p-1.5 rounded-cm text-cm-text-muted/50 hover:text-cm-error hover:bg-cm-error/10 transition-all"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
            <% end %>
          <% end %>

          <%= for err <- upload_errors(@uploads.photo) do %>
            <p class="text-cm-error text-sm mt-2">{upload_error_to_string(err)}</p>
          <% end %>
        </div>
      </div>

      <%!-- Given name --%>
      <.input field={@form[:given_name]} label={gettext("Given name")} required />

      <%!-- Surname --%>
      <.input field={@form[:surname]} label={gettext("Surname")} />

      <%!-- Gender --%>
      <div>
        <label class="font-cm-mono text-[10px] uppercase tracking-wider text-cm-text-muted">
          {gettext("Gender")}
        </label>
        <div class="flex items-center gap-4 mt-1">
          <label class="flex items-center gap-1.5 cursor-pointer">
            <input
              type="radio"
              name={@form[:gender].name}
              value="female"
              checked={to_string(@form[:gender].value) == "female"}
              class="w-4 h-4 accent-cm-indigo"
            />
            <span class="text-sm text-cm-black">{gettext("Female")}</span>
          </label>
          <label class="flex items-center gap-1.5 cursor-pointer">
            <input
              type="radio"
              name={@form[:gender].name}
              value="male"
              checked={to_string(@form[:gender].value) == "male"}
              class="w-4 h-4 accent-cm-indigo"
            />
            <span class="text-sm text-cm-black">{gettext("Male")}</span>
          </label>
          <label class="flex items-center gap-1.5 cursor-pointer">
            <input
              type="radio"
              name={@form[:gender].name}
              value="other"
              checked={to_string(@form[:gender].value) == "other"}
              class="w-4 h-4 accent-cm-indigo"
            />
            <span class="text-sm text-cm-black">{gettext("Other")}</span>
          </label>
        </div>
      </div>

      <%!-- Birth date --%>
      <div>
        <label class="font-cm-mono text-[10px] uppercase tracking-wider text-cm-text-muted">
          {gettext("Birth date")}
        </label>
        <div class="flex items-center gap-2 mt-1">
          <select
            name={@form[:birth_day].name}
            id={@form[:birth_day].id}
            class="bg-cm-white border-2 border-cm-black rounded-cm px-2 py-1 text-sm font-cm-body text-cm-black"
          >
            <option value="">{gettext("Day")}</option>
            <%= for {label, val} <- day_options() do %>
              <option value={val} selected={to_string(@form[:birth_day].value) == val}>
                {label}
              </option>
            <% end %>
          </select>
          <select
            name={@form[:birth_month].name}
            id={@form[:birth_month].id}
            class="bg-cm-white border-2 border-cm-black rounded-cm px-2 py-1 text-sm font-cm-body text-cm-black"
          >
            <option value="">{gettext("Month")}</option>
            <%= for {label, val} <- month_options() do %>
              <option value={val} selected={to_string(@form[:birth_month].value) == val}>
                {label}
              </option>
            <% end %>
          </select>
          <input
            type="number"
            name={@form[:birth_year].name}
            id={@form[:birth_year].id}
            value={@form[:birth_year].value}
            min="1000"
            max="2100"
            placeholder={gettext("Year")}
            class="bg-cm-white border-2 border-cm-black rounded-cm px-2 py-1 text-sm font-cm-body text-cm-black w-24"
          />
        </div>
      </div>

      <%!-- Acquaintance checkbox --%>
      <%= if @show_acquaintance do %>
        <div>
          <label
            class="flex items-center gap-2 cursor-pointer"
            {test_id("quick-person-acquaintance-label")}
          >
            <input type="hidden" name="person[kind]" value="family_member" />
            <input
              type="checkbox"
              name="person[kind]"
              value="acquaintance"
              checked={to_string(@form[:kind].value) == "acquaintance"}
              class="w-4 h-4 accent-cm-indigo rounded"
              {test_id("quick-person-acquaintance-checkbox")}
            />
            <span class="text-sm text-cm-black">
              {gettext("This person is not a family member (acquaintance)")}
            </span>
          </label>
        </div>
      <% end %>

      <%!-- Action buttons --%>
      <div class="flex gap-3 pt-2">
        <button
          type="submit"
          id={"#{@id}-submit"}
          class="flex-1 bg-cm-indigo text-cm-white rounded-cm py-2.5 font-cm-mono text-[10px] font-bold uppercase tracking-wider hover:bg-cm-indigo-hover transition-colors"
          {test_id("quick-person-submit")}
        >
          {gettext("Create")}
        </button>
        <button
          type="button"
          phx-click="cancel"
          phx-target={@myself}
          class="flex-1 border-2 border-cm-black bg-cm-white text-cm-black rounded-cm py-2.5 font-cm-mono text-[10px] font-bold uppercase tracking-wider hover:bg-cm-surface transition-colors"
        >
          {gettext("Cancel")}
        </button>
      </div>
    </.form>
    """
  end

  @impl true
  def handle_event("validate", %{"person" => params}, socket) do
    changeset =
      %Person{}
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :person))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    case create_person(socket.assigns, params) do
      {:ok, person} ->
        person = maybe_process_photo(socket, person)
        send(self(), {:person_created, person})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :person))}
    end
  end

  def handle_event("cancel", _, socket) do
    send(self(), {:quick_person_cancelled})
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  # --- Private helpers ---

  defp create_person(%{family_id: family_id}, params) when not is_nil(family_id) do
    family = Families.get_family!(family_id)
    People.create_person(family, params)
  end

  defp create_person(%{organization_id: org_id}, params) do
    org = Organizations.get_organization!(org_id)
    People.create_person_without_family(org, params)
  end

  defp maybe_process_photo(socket, person) do
    entries = socket.assigns.uploads.photo.entries
    all_done? = entries != [] and Enum.all?(entries, & &1.done?)

    if all_done? do
      [original_path] =
        consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
          uuid = Ecto.UUID.generate()
          ext = Path.extname(entry.client_name)
          dest_key = Path.join(["uploads", "originals", uuid, "photo#{ext}"])
          original_path = Ancestry.Storage.store_original(tmp_path, dest_key)
          {:ok, original_path}
        end)

      People.update_photo_pending(person, original_path)
      People.get_person!(person.id)
    else
      person
    end
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
