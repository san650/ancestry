defmodule Web.Components.PhotoGallery do
  use Phoenix.Component
  use Gettext, backend: Web.Gettext

  import Web.CoreComponents
  import Web.Helpers.TestHelpers
  alias Web.Comments.PhotoCommentsComponent

  alias Phoenix.LiveView.JS

  @doc """
  Renders a masonry or uniform photo grid from a stream.
  """
  attr :id, :string, required: true
  attr :photos, :any, required: true
  attr :grid_layout, :atom, default: :masonry
  attr :selection_mode, :boolean, default: false
  attr :selected_ids, :any, default: nil

  def photo_grid(assigns) do
    assigns = assign_new(assigns, :selected_ids, fn -> MapSet.new() end)

    ~H"""
    <div
      id={@id}
      phx-update="stream"
      class={[
        if(@grid_layout == :masonry,
          do: "masonry-grid columns-2 sm:columns-3 md:columns-4 lg:columns-5 gap-2",
          else: "uniform-grid grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-2"
        )
      ]}
    >
      <div
        id={"#{@id}-empty"}
        class="hidden only:block col-span-full text-center py-20 text-ds-on-surface-variant/50"
      >
        No photos yet
      </div>
      <div
        :for={{id, photo} <- @photos}
        id={id}
        class={[
          "relative group rounded-ds-sharp overflow-hidden bg-ds-surface-low cursor-pointer",
          @grid_layout == :masonry && "mb-2 break-inside-avoid",
          if(@selection_mode && MapSet.member?(@selected_ids, photo.id),
            do: "outline outline-3 outline-ds-primary outline-offset-2",
            else: "outline outline-3 outline-transparent outline-offset-2"
          )
        ]}
        phx-click={JS.push("photo_clicked", value: %{id: photo.id})}
      >
        <%= cond do %>
          <% photo.status == "pending" -> %>
            <div class="aspect-square flex flex-col items-center justify-center gap-2">
              <.icon
                name="hero-photo"
                class="w-8 h-8 text-ds-on-surface-variant/50 animate__animated animate__pulse animate__infinite"
              />
              <p class="text-xs text-ds-on-surface-variant/50 font-ds-body font-medium">Processing</p>
            </div>
          <% photo.status == "failed" -> %>
            <div class="aspect-square flex flex-col items-center justify-center gap-2 bg-ds-error/5">
              <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-ds-error/50" />
              <p class="text-xs text-ds-error/70">Processing failed</p>
            </div>
          <% true -> %>
            <img
              src={Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)}
              alt={photo.original_filename}
              class="w-full h-full object-cover"
              loading="lazy"
            />
        <% end %>

        <%= if @selection_mode do %>
          <div class={[
            "absolute inset-0 transition-colors",
            MapSet.member?(@selected_ids, photo.id) && "bg-ds-primary/30"
          ]}>
            <div class={[
              "absolute top-2 right-2 w-6 h-6 rounded-full border-2 transition-all flex items-center justify-center",
              if(MapSet.member?(@selected_ids, photo.id),
                do: "bg-ds-primary border-ds-primary",
                else: "border-white/70 bg-black/20"
              )
            ]}>
              <%= if MapSet.member?(@selected_ids, photo.id) do %>
                <.icon name="hero-check" class="w-3.5 h-3.5 text-white" />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a full-screen photo lightbox with navigation, people panel, and comments.
  """
  attr :selected_photo, :any, required: true
  attr :photos, :list, required: true
  attr :panel_open, :boolean, default: false
  attr :photo_people, :list, default: []
  attr :current_scope, :any, required: true

  def lightbox(assigns) do
    current_index = Enum.find_index(assigns.photos, &(&1.id == assigns.selected_photo.id)) || 0
    total_photos = length(assigns.photos)

    assigns =
      assigns
      |> assign(:current_index, current_index)
      |> assign(:total_photos, total_photos)

    ~H"""
    <div
      id="lightbox"
      class="fixed inset-0 z-50 bg-black flex flex-col select-none"
      phx-window-keydown="lightbox_keydown"
    >
      <%!-- Lightbox top bar --%>
      <div class="shrink-0 flex items-center justify-between px-4 py-3 text-white">
        <%!-- Close button --%>
        <button
          type="button"
          phx-click="close_lightbox"
          class="p-2 hover:bg-white/10 rounded-ds-sharp"
          aria-label="Close"
        >
          <.icon name="hero-x-mark" class="size-6" />
        </button>

        <%!-- Position indicator: mobile only --%>
        <span :if={@total_photos > 1} class="text-sm text-white/70 font-ds-body lg:hidden">
          {@current_index + 1} of {@total_photos}
        </span>

        <%!-- Desktop: filename --%>
        <span class="hidden lg:block text-sm text-white/70 font-ds-body truncate max-w-xs">
          {@selected_photo.original_filename}
        </span>

        <%!-- Right actions --%>
        <div class="flex items-center gap-1">
          <%!-- Info/comments toggle --%>
          <button
            id="toggle-panel-btn"
            type="button"
            phx-click="toggle_panel"
            class={[
              "p-2 hover:bg-white/10 rounded-ds-sharp",
              if(@panel_open, do: "text-ds-primary bg-white/10", else: "text-white/50")
            ]}
            aria-label="Photo info"
          >
            <.icon name="hero-information-circle" class="size-6" />
          </button>
          <%!-- Download: desktop only --%>
          <a
            href={Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :original)}
            download={@selected_photo.original_filename}
            class="p-2 hover:bg-white/10 rounded-ds-sharp hidden lg:block text-white/50 hover:text-white"
            aria-label="Download"
          >
            <.icon name="hero-arrow-down-tray" class="size-6" />
          </a>
        </div>
      </div>

      <%!-- Main image area + comments panel --%>
      <div class="flex-1 flex min-h-0">
        <div
          id="lightbox-swipe"
          phx-hook="Swipe"
          class={[
            "flex-1 flex items-center justify-center relative min-h-0 px-4 lg:px-16",
            @panel_open && "lg:flex-[2]"
          ]}
        >
          <%!-- Navigation arrows: desktop only --%>
          <button
            phx-click={JS.push("lightbox_keydown", value: %{key: "ArrowLeft"})}
            class="hidden lg:block absolute left-3 p-3 text-white/40 hover:text-white hover:bg-white/10 rounded-full transition-colors z-10"
          >
            <.icon name="hero-chevron-left" class="w-7 h-7" />
          </button>

          <img
            id="lightbox-image"
            src={Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :large)}
            alt={@selected_photo.original_filename}
            class="max-h-full max-w-full object-contain rounded-ds-sharp shadow-2xl"
            phx-hook="PhotoTagger"
          />

          <button
            phx-click={JS.push("lightbox_keydown", value: %{key: "ArrowRight"})}
            class="hidden lg:block absolute right-3 p-3 text-white/40 hover:text-white hover:bg-white/10 rounded-full transition-colors z-10"
          >
            <.icon name="hero-chevron-right" class="w-7 h-7" />
          </button>
        </div>

        <%= if @panel_open do %>
          <%!-- Info panel: full-screen overlay on mobile, side panel on desktop --%>
          <%!-- L1 panel base — no border, slightly lifted from the lightbox black backdrop --%>
          <div class={[
            "fixed inset-0 z-50 flex flex-col bg-black text-white",
            "lg:static lg:inset-auto lg:z-auto lg:w-80 lg:shrink-0"
          ]}>
            <div class="flex flex-col h-full bg-white/[0.03] p-2 gap-2">
              <%!-- Panel header — close X, no bottom border --%>
              <div class="flex items-center justify-between px-2 py-2 shrink-0">
                <h3 class="text-sm font-ds-heading font-bold text-white/90">
                  {gettext("Photo info")}
                </h3>
                <button
                  type="button"
                  phx-click="toggle_panel"
                  class="p-2 -mr-2 rounded-ds-sharp text-white/50 hover:text-white hover:bg-white/[0.10] min-w-[44px] min-h-[44px] lg:min-w-0 lg:min-h-0 lg:p-1.5 flex items-center justify-center"
                  aria-label={gettext("Close info")}
                >
                  <.icon name="hero-x-mark" class="size-5 lg:w-4 lg:h-4" />
                </button>
              </div>

              <%!-- People card (L2) --%>
              <div
                {test_id("lightbox-people-card")}
                class="bg-white/[0.06] rounded-ds-sharp p-2.5 flex flex-col gap-2 shrink-0 max-h-[30vh] lg:max-h-none overflow-hidden"
              >
                <div class="flex items-center gap-2 px-1">
                  <h4 class="text-xs font-ds-heading font-bold text-white/90 tracking-wide uppercase">
                    {gettext("People")}
                  </h4>
                  <span
                    :if={@photo_people != []}
                    class="text-[11px] text-white/50 bg-white/[0.10] px-1.5 py-0.5 rounded-full"
                  >
                    {length(@photo_people)}
                  </span>
                </div>

                <div id="photo-person-list" class="overflow-y-auto">
                  <%= if @photo_people == [] do %>
                    <div class="text-center py-5 text-white/50">
                      <div class="inline-flex items-center justify-center w-8 h-8 rounded-full bg-white/[0.04] mb-2">
                        <.icon name="hero-user" class="w-4 h-4 text-white/40" />
                      </div>
                      <p class="text-[12.5px] leading-snug">
                        <span class="lg:hidden">{gettext("No people tagged yet.")}</span>
                        <span class="hidden lg:inline">
                          {gettext("Click on the photo to tag people")}
                        </span>
                      </p>
                    </div>
                  <% else %>
                    <div class="flex flex-col">
                      <%= for pp <- @photo_people do %>
                        <div
                          id={"photo-person-#{pp.id}"}
                          class="group flex items-center gap-3 lg:gap-2 px-1.5 py-2 lg:py-1.5 rounded-ds-sharp hover:bg-white/[0.06] transition-colors min-h-[44px] lg:min-h-0"
                          data-person-id={pp.person_id}
                          phx-hook="PersonHighlight"
                        >
                          <%= if pp.person.photo && pp.person.photo_status == "processed" do %>
                            <img
                              src={
                                Ancestry.Uploaders.PersonPhoto.url(
                                  {pp.person.photo, pp.person},
                                  :thumbnail
                                )
                              }
                              class="w-7 h-7 lg:w-6 lg:h-6 rounded-full object-cover shrink-0"
                            />
                          <% else %>
                            <div class="w-7 h-7 lg:w-6 lg:h-6 rounded-full bg-white/[0.10] flex items-center justify-center shrink-0">
                              <.icon name="hero-user" class="w-4 h-4 lg:w-3.5 lg:h-3.5 text-white/40" />
                            </div>
                          <% end %>
                          <span class="text-sm text-white/85 truncate flex-1">
                            {Ancestry.People.Person.display_name(pp.person)}
                          </span>
                          <button
                            phx-click="untag_person"
                            phx-value-photo-id={pp.photo_id}
                            phx-value-person-id={pp.person_id}
                            class="p-2 lg:p-1 rounded text-white/40 hover:text-red-400 lg:opacity-0 lg:group-hover:opacity-100 transition-all shrink-0"
                            title={gettext("Remove tag")}
                          >
                            <.icon name="hero-x-mark" class="w-4 h-4 lg:w-3.5 lg:h-3.5" />
                          </button>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>

              <%!-- Comments card (L2) — wraps the live component --%>
              <div
                {test_id("lightbox-comments-card")}
                class="bg-white/[0.06] rounded-ds-sharp flex-1 min-h-0 flex flex-col overflow-hidden"
              >
                <.live_component
                  module={PhotoCommentsComponent}
                  id="photo-comments"
                  photo_id={@selected_photo.id}
                  current_scope={@current_scope}
                />
              </div>

              <%!-- Download tonal block: mobile only --%>
              <a
                href={
                  Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :original)
                }
                download={@selected_photo.original_filename}
                class="lg:hidden shrink-0 flex items-center justify-center gap-2 bg-white/[0.10] rounded-ds-sharp py-3 text-sm font-ds-body font-semibold text-white/90 hover:bg-white/[0.16] transition-colors"
              >
                <.icon name="hero-arrow-down-tray" class="size-5" /> {gettext("Download")}
              </a>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Thumbnail strip: desktop only --%>
      <div class="hidden lg:flex shrink-0 gap-2 px-6 py-4 overflow-x-auto">
        <%= for photo <- @photos do %>
          <button
            phx-click="lightbox_select"
            phx-value-id={photo.id}
            class={[
              "shrink-0 w-16 h-16 rounded-ds-sharp overflow-hidden border-2 transition-all duration-150",
              if(photo.id == @selected_photo.id,
                do: "border-white scale-105 shadow-lg",
                else: "border-transparent opacity-50 hover:opacity-90"
              )
            ]}
          >
            <%= if photo.status == "processed" do %>
              <img
                src={Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)}
                alt={photo.original_filename}
                class="w-full h-full object-cover"
              />
            <% else %>
              <div class="w-full h-full bg-white/10 flex items-center justify-center">
                <.icon name="hero-photo" class="w-5 h-5 text-white/30" />
              </div>
            <% end %>
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end
