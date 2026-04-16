defmodule Web.Components.AvatarComponents do
  @moduledoc "Shared avatar rendering components."
  use Phoenix.Component

  alias Ancestry.Avatars
  alias Ancestry.Uploaders.AccountAvatar

  attr :account, :any, required: true, doc: "Account struct or nil"
  attr :size, :atom, default: :md, values: [:sm, :md], doc: ":sm = 22px, :md = 28px"
  attr :class, :string, default: ""

  def user_avatar(assigns) do
    size_classes =
      case assigns.size do
        :sm -> "w-[22px] h-[22px] text-[9px]"
        :md -> "w-7 h-7 text-[11px]"
      end

    assigns =
      assigns
      |> assign(:size_classes, size_classes)
      |> assign(:initials, Avatars.initials(assigns.account))
      |> assign(:bg_color, Avatars.color(account_id(assigns.account)))
      |> assign(:avatar_url, avatar_url(assigns.account))

    ~H"""
    <%= if @avatar_url do %>
      <img
        src={@avatar_url}
        class={["rounded-full object-cover flex-shrink-0", @size_classes, @class]}
        alt={@initials}
      />
    <% else %>
      <div
        class={[
          "rounded-full flex items-center justify-center flex-shrink-0 font-semibold text-white",
          @size_classes,
          @class
        ]}
        style={"background-color: #{@bg_color}"}
      >
        {@initials}
      </div>
    <% end %>
    """
  end

  defp account_id(nil), do: nil
  defp account_id(%{id: id}), do: id

  defp avatar_url(nil), do: nil

  defp avatar_url(%{avatar: avatar, avatar_status: "processed"} = account)
       when not is_nil(avatar) do
    AccountAvatar.url({avatar, account}, :thumbnail)
  end

  defp avatar_url(_), do: nil
end
