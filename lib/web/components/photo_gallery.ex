defmodule Web.Components.PhotoGallery do
  use Phoenix.Component

  import Web.CoreComponents
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
        class="hidden only:block col-span-full text-center py-20 text-base-content/30"
      >
        No photos yet
      </div>
      <div
        :for={{id, photo} <- @photos}
        id={id}
        class={[
          "relative group rounded-xl overflow-hidden bg-base-200 cursor-pointer",
          @grid_layout == :masonry && "mb-2 break-inside-avoid",
          if(@selection_mode && MapSet.member?(@selected_ids, photo.id),
            do: "outline outline-3 outline-primary outline-offset-2",
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
                class="w-8 h-8 text-base-content/20 animate__animated animate__pulse animate__infinite"
              />
              <p class="text-xs text-base-content/30 font-medium">Processing</p>
            </div>
          <% photo.status == "failed" -> %>
            <div class="aspect-square flex flex-col items-center justify-center gap-2 bg-error/5">
              <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-error/50" />
              <p class="text-xs text-error/70">Processing failed</p>
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
            MapSet.member?(@selected_ids, photo.id) && "bg-primary/30"
          ]}>
            <div class={[
              "absolute top-2 right-2 w-6 h-6 rounded-full border-2 transition-all flex items-center justify-center",
              if(MapSet.member?(@selected_ids, photo.id),
                do: "bg-primary border-primary",
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

  def lightbox(assigns) do
    ~H"""
    <div
      id="lightbox"
      class="fixed inset-0 z-50 bg-black/95 flex flex-col select-none"
      phx-window-keydown="lightbox_keydown"
    >
      <%!-- Lightbox top bar --%>
      <div class="flex items-center justify-between px-6 py-4 shrink-0">
        <p class="text-white/50 text-sm truncate max-w-xs">{@selected_photo.original_filename}</p>
        <div class="flex items-center gap-3">
          <a
            href={Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :original)}
            download={@selected_photo.original_filename}
            class="flex items-center gap-1.5 px-3 py-1.5 bg-white/10 hover:bg-white/20 text-white rounded-lg text-sm font-medium transition-colors"
          >
            <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Download original
          </a>
          <button
            id="toggle-panel-btn"
            phx-click="toggle_panel"
            class={[
              "p-2 rounded-lg transition-colors",
              if(@panel_open,
                do: "text-primary bg-white/10",
                else: "text-white/50 hover:text-white hover:bg-white/10"
              )
            ]}
            title="Toggle panel"
          >
            <.icon name="hero-information-circle" class="w-5 h-5" />
          </button>
          <button
            phx-click="close_lightbox"
            class="p-2 text-white/50 hover:text-white rounded-lg hover:bg-white/10 transition-colors"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>
      </div>

      <%!-- Main image area + comments panel --%>
      <div class="flex-1 flex min-h-0">
        <div class={[
          "flex-1 flex items-center justify-center relative min-h-0 px-16",
          @panel_open && "lg:flex-[2]"
        ]}>
          <button
            phx-click={JS.push("lightbox_keydown", value: %{key: "ArrowLeft"})}
            class="absolute left-3 p-3 text-white/40 hover:text-white hover:bg-white/10 rounded-full transition-colors z-10"
          >
            <.icon name="hero-chevron-left" class="w-7 h-7" />
          </button>

          <img
            id="lightbox-image"
            src={Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :large)}
            alt={@selected_photo.original_filename}
            class="max-h-full max-w-full object-contain rounded-lg shadow-2xl"
            phx-hook="PhotoTagger"
          />

          <button
            phx-click={JS.push("lightbox_keydown", value: %{key: "ArrowRight"})}
            class="absolute right-3 p-3 text-white/40 hover:text-white hover:bg-white/10 rounded-full transition-colors z-10"
          >
            <.icon name="hero-chevron-right" class="w-7 h-7" />
          </button>
        </div>

        <%= if @panel_open do %>
          <div class="hidden lg:flex flex-col w-80 shrink-0 border-l border-white/10 bg-black/80 text-white">
            <%!-- People section --%>
            <div class="shrink-0 border-b border-white/10">
              <div class="flex items-center justify-between px-4 py-3">
                <div class="flex items-center gap-2">
                  <h3 class="text-sm font-semibold text-white/90 tracking-wide">People</h3>
                  <%= if @photo_people != [] do %>
                    <span class="text-xs bg-white/10 text-white/60 px-1.5 py-0.5 rounded-full">
                      {length(@photo_people)}
                    </span>
                  <% end %>
                </div>
                <button
                  phx-click="toggle_panel"
                  class="p-1.5 rounded-lg text-white/40 hover:text-white hover:bg-white/10 transition-colors"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
              <div id="photo-person-list" class="px-4 pb-3 max-h-48 overflow-y-auto">
                <%= if @photo_people == [] do %>
                  <p class="text-sm text-white/30 py-2">Click on the photo to tag people</p>
                <% else %>
                  <div class="space-y-1">
                    <%= for pp <- @photo_people do %>
                      <div
                        id={"photo-person-#{pp.id}"}
                        class="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-white/10 transition-colors group"
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
                            class="w-6 h-6 rounded-full object-cover shrink-0"
                          />
                        <% else %>
                          <div class="w-6 h-6 rounded-full bg-white/10 flex items-center justify-center shrink-0">
                            <.icon name="hero-user" class="w-3.5 h-3.5 text-white/40" />
                          </div>
                        <% end %>
                        <span class="text-sm text-white/80 truncate flex-1">
                          {Ancestry.People.Person.display_name(pp.person)}
                        </span>
                        <button
                          phx-click="untag_person"
                          phx-value-photo-id={pp.photo_id}
                          phx-value-person-id={pp.person_id}
                          class="p-1 rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all shrink-0"
                          title="Remove tag"
                        >
                          <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Comments section --%>
            <div class="flex-1 min-h-0">
              <.live_component
                module={PhotoCommentsComponent}
                id="photo-comments"
                photo_id={@selected_photo.id}
              />
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Thumbnail strip --%>
      <div class="shrink-0 flex gap-2 px-6 py-4 overflow-x-auto">
        <%= for photo <- @photos do %>
          <button
            phx-click="lightbox_select"
            phx-value-id={photo.id}
            class={[
              "shrink-0 w-16 h-16 rounded-lg overflow-hidden border-2 transition-all duration-150",
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
