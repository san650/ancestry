defmodule Web.FamilyLive.UnionConnectorComponent do
  use Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex items-center justify-center h-full min-h-[3rem]">
      <div class={[
        "w-full h-0.5",
        if(@type == :partner,
          do: "bg-zinc-300 dark:bg-zinc-600",
          else: "bg-zinc-300/50 dark:bg-zinc-600/50"
        )
      ]}>
      </div>
    </div>
    """
  end
end
