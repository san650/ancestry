defmodule Web.BirthdayLive.Index do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    today = Date.utc_today()
    all_people = People.list_birthdays_for_family(family_id)
    show_all = false
    visible = filter_people(all_people, show_all)
    months = group_by_month(visible, today)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:all_people, all_people)
     |> assign(:show_all, show_all)
     |> assign(:months, months)
     |> assign(:today, today)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <:toolbar>
        <div class="max-w-7xl mx-auto flex items-center justify-between py-3">
          <div class="flex items-center gap-3">
            <%!-- Hamburger: mobile only --%>
            <button
              type="button"
              phx-click={toggle_nav_drawer()}
              class="p-2 -ml-2 text-cm-text-muted hover:text-cm-black lg:hidden min-w-[44px] min-h-[44px] flex items-center justify-center"
              aria-label={gettext("Open menu")}
            >
              <.icon name="hero-bars-3" class="size-5" />
            </button>
            <.breadcrumb
              items={[
                %{
                  label: @current_scope.organization.name,
                  navigate: ~p"/org/#{@current_scope.organization.id}"
                },
                %{
                  label: @family.name,
                  navigate: ~p"/org/#{@current_scope.organization.id}/families/#{@family.id}"
                }
              ]}
              current={gettext("Birthdays")}
            />
          </div>
          <div class="flex items-center gap-2">
            <.toolbar_button
              variant={:filter}
              active={@show_all}
              phx-click="toggle_show_all"
              {test_id("show-all-toggle")}
            >
              {gettext("Show all")}
            </.toolbar_button>
          </div>
        </div>
      </:toolbar>

      <%!-- Nav drawer (mobile) --%>
      <.nav_drawer current_scope={@current_scope} />

      <div class="max-w-lg mx-auto px-4 py-6">
        <div id="birthday-calendar">
          <%= for month <- @months do %>
            <div class="mb-6">
              <div class={[
                "sticky top-0 z-10 py-2 px-3 bg-cm-surface/80 backdrop-blur-sm border-b border-cm-border/30 mb-2",
                month.is_past && "opacity-50"
              ]}>
                <span class="font-cm-display font-bold text-sm text-cm-indigo uppercase tracking-wider">
                  {month.name}
                </span>
              </div>

              <%= if month.entries == [] do %>
                <p class="text-sm text-cm-text-muted/60 px-3 py-4">
                  {gettext("No birthdays")}
                </p>
              <% else %>
                <%= for entry <- month.entries do %>
                  <%= if entry == :today_marker do %>
                    <div
                      id="today-marker"
                      class="flex items-center gap-2 my-3 px-3"
                      phx-hook="ScrollToToday"
                    >
                      <div class="flex-1 h-0.5 bg-cm-coral"></div>
                      <span class="font-cm-mono text-[10px] font-bold text-cm-coral uppercase tracking-wider whitespace-nowrap">
                        {gettext("TODAY")} · {format_today(@today)}
                      </span>
                      <div class="flex-1 h-0.5 bg-cm-coral"></div>
                    </div>
                  <% else %>
                    <.link
                      navigate={
                        ~p"/org/#{@current_scope.organization.id}/people/#{entry.person.id}?from_family=#{@family.id}"
                      }
                      class={[
                        "flex items-center gap-3 px-3 py-2.5 rounded-cm border-2 border-cm-black bg-cm-white mb-1.5 hover:bg-cm-surface transition-colors",
                        entry.is_past && "opacity-45"
                      ]}
                      {test_id("birthday-entry-#{entry.person.id}")}
                    >
                      <%!-- Date box --%>
                      <div class="flex-shrink-0 bg-cm-surface rounded-cm border border-cm-border px-2.5 py-1.5 text-center min-w-[48px]">
                        <div class="font-cm-display text-lg font-bold text-cm-indigo leading-none">
                          {entry.person.birth_day}
                        </div>
                        <div class="font-cm-mono text-[9px] font-semibold text-cm-text-muted uppercase tracking-wider">
                          {month_abbrev(entry.person.birth_month)}
                        </div>
                      </div>
                      <%!-- Avatar --%>
                      <div class="w-9 h-9 rounded-full bg-cm-surface flex items-center justify-center overflow-hidden flex-shrink-0">
                        <%= if entry.person.photo && entry.person.photo_status == "processed" do %>
                          <img
                            src={
                              Ancestry.Uploaders.PersonPhoto.url(
                                {entry.person.photo, entry.person},
                                :thumbnail
                              )
                            }
                            alt={Person.display_name(entry.person)}
                            class="w-full h-full object-cover"
                          />
                        <% else %>
                          <.icon
                            name="hero-user"
                            class={["w-4 h-4", gender_icon_class(entry.person.gender)]}
                          />
                        <% end %>
                      </div>
                      <%!-- Name + age --%>
                      <div class="flex-1 min-w-0">
                        <div class="font-cm-body text-[13px] font-medium text-cm-black truncate">
                          {Person.display_name(entry.person)}
                          <%= if entry.person.deceased do %>
                            <span class="font-cm-mono text-[10px] font-normal text-cm-text-muted">
                              ({deceased_label(entry.person.gender)})
                            </span>
                          <% end %>
                        </div>
                        <%= if entry.age_label do %>
                          <div class="font-cm-mono text-[10px] text-cm-text-muted">
                            {entry.age_label}
                          </div>
                        <% end %>
                      </div>
                    </.link>
                  <% end %>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("toggle_show_all", _, socket) do
    show_all = !socket.assigns.show_all
    visible = filter_people(socket.assigns.all_people, show_all)
    months = group_by_month(visible, socket.assigns.today)

    {:noreply,
     socket
     |> assign(:show_all, show_all)
     |> assign(:months, months)}
  end

  # --- Helpers ---

  defp filter_people(people, true), do: people
  defp filter_people(people, false), do: Enum.reject(people, & &1.deceased)

  defp group_by_month(people, today) do
    people_by_month = Enum.group_by(people, & &1.birth_month)

    for month_num <- 1..12 do
      month_people = Map.get(people_by_month, month_num, [])
      is_past_month = month_num < today.month

      entries = build_entries(month_people, month_num, today)

      %{
        number: month_num,
        name: month_name(month_num),
        is_past: is_past_month && !Enum.any?(entries, &(&1 == :today_marker)),
        entries: entries
      }
    end
  end

  defp build_entries(people, month_num, today) do
    entries =
      Enum.map(people, fn person ->
        is_past = birthday_is_past?(person.birth_month, person.birth_day, today)

        %{
          person: person,
          is_past: is_past,
          age_label: age_label(person, today)
        }
      end)

    if month_num == today.month do
      {past, future} = Enum.split_with(entries, & &1.is_past)
      past ++ [:today_marker] ++ future
    else
      entries
    end
  end

  defp birthday_is_past?(birth_month, birth_day, today) do
    # Leap day edge case: on non-leap years, treat Feb 29 as Feb 28
    effective_day =
      if birth_month == 2 and birth_day == 29 and not Date.leap_year?(today) do
        28
      else
        birth_day
      end

    {birth_month, effective_day} < {today.month, today.day}
  end

  defp compute_age(birth_year, birth_month, birth_day, today) do
    base_age = today.year - birth_year
    if {today.month, today.day} < {birth_month, birth_day}, do: base_age - 1, else: base_age
  end

  defp age_label(%{birth_year: nil}, _today), do: nil

  defp age_label(person, today) do
    age = compute_age(person.birth_year, person.birth_month, person.birth_day, today)

    is_today =
      {person.birth_month, person.birth_day} == {today.month, today.day} or
        (person.birth_month == 2 and person.birth_day == 29 and
           not Date.leap_year?(today) and today.month == 2 and today.day == 28)

    cond do
      person.deceased ->
        gettext("Would have turned %{age}", age: age)

      is_today ->
        gettext("Turns %{age} today!", age: age)

      birthday_is_past?(person.birth_month, person.birth_day, today) ->
        gettext("Turned %{age}", age: age)

      true ->
        gettext("Turns %{age}", age: age)
    end
  end

  defp month_name(1), do: gettext("January")
  defp month_name(2), do: gettext("February")
  defp month_name(3), do: gettext("March")
  defp month_name(4), do: gettext("April")
  defp month_name(5), do: gettext("May")
  defp month_name(6), do: gettext("June")
  defp month_name(7), do: gettext("July")
  defp month_name(8), do: gettext("August")
  defp month_name(9), do: gettext("September")
  defp month_name(10), do: gettext("October")
  defp month_name(11), do: gettext("November")
  defp month_name(12), do: gettext("December")

  defp month_abbrev(1), do: gettext("Jan")
  defp month_abbrev(2), do: gettext("Feb")
  defp month_abbrev(3), do: gettext("Mar")
  defp month_abbrev(4), do: gettext("Apr")
  defp month_abbrev(5), do: gettext("May")
  defp month_abbrev(6), do: gettext("Jun")
  defp month_abbrev(7), do: gettext("Jul")
  defp month_abbrev(8), do: gettext("Aug")
  defp month_abbrev(9), do: gettext("Sep")
  defp month_abbrev(10), do: gettext("Oct")
  defp month_abbrev(11), do: gettext("Nov")
  defp month_abbrev(12), do: gettext("Dec")

  defp format_today(date) do
    "#{month_abbrev(date.month) |> String.upcase()} #{date.day}"
  end

  defp deceased_label("male"), do: pgettext("male", "deceased")
  defp deceased_label("female"), do: pgettext("female", "deceased")
  defp deceased_label(_), do: pgettext("other", "deceased")

  defp gender_icon_class("male"), do: "text-blue-400"
  defp gender_icon_class("female"), do: "text-pink-400"
  defp gender_icon_class(_), do: "text-cm-indigo"
end
