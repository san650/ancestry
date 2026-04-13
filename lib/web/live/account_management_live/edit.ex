defmodule Web.AccountManagementLive.Edit do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Identity.Account,
    scope_subject: &Function.identity/1,
    skip_preload: [:index, :new, :show, :edit]

  alias Ancestry.Identity
  alias Ancestry.Identity.Account
  alias Ancestry.Identity.AccountToken
  alias Ancestry.Organizations

  @impl true
  def handle_unauthorized(_action, socket) do
    {:halt,
     socket
     |> put_flash(:error, "You don't have permission to access this page")
     |> push_navigate(to: ~p"/org")}
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    account = Identity.get_account_with_orgs!(id)
    changeset = Account.admin_changeset(account, %{}, mode: :edit)
    organizations = Organizations.list_organizations()
    selected_org_ids = Enum.map(account.organizations, & &1.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "account:#{id}")
    end

    {:ok,
     socket
     |> assign(:page_title, "Edit Account")
     |> assign(:account, account)
     |> assign(:form, to_form(changeset))
     |> assign(:organizations, organizations)
     |> assign(:selected_org_ids, selected_org_ids)
     |> assign(:confirm_deactivate, false)
     |> assign(:confirm_reactivate, false)
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"account" => account_params}, socket) do
    changeset =
      socket.assigns.account
      |> Account.admin_changeset(account_params, mode: :edit)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"account" => account_params} = params, socket) do
    account = socket.assigns.account
    current_account = socket.assigns.current_scope.account
    org_ids = params["organization_ids"] || []

    avatar_original_path =
      consume_uploaded_entries(socket, :avatar, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = Path.extname(entry.client_name)
        dest_key = Path.join(["uploads", "originals", uuid, "avatar#{ext}"])
        original_path = Ancestry.Storage.store_original(tmp_path, dest_key)
        {:ok, original_path}
      end)
      |> List.first()

    case Identity.update_admin_account(account, account_params, current_account) do
      {:ok, updated_account} ->
        Identity.update_account_organizations(updated_account, org_ids)

        if avatar_original_path do
          Identity.update_avatar_status(updated_account, "pending")

          %{account_id: updated_account.id, original_path: avatar_original_path}
          |> Ancestry.Workers.ProcessAccountAvatarJob.new()
          |> Oban.insert()
        end

        password = account_params["password"]

        if is_binary(password) and password != "" do
          import Ecto.Query
          tokens = Ancestry.Repo.all(from(t in AccountToken, where: t.account_id == ^account.id))
          Ancestry.Repo.delete_all(from(t in AccountToken, where: t.account_id == ^account.id))
          Web.AccountAuth.disconnect_sessions(tokens)
        end

        {:noreply,
         socket
         |> put_flash(:info, "Account updated successfully.")
         |> push_navigate(to: ~p"/admin/accounts/#{updated_account.id}")}

      {:error, :cannot_change_own_role} ->
        {:noreply, put_flash(socket, :error, "You cannot change your own role.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("toggle_org", %{"org-id" => org_id}, socket) do
    selected = socket.assigns.selected_org_ids

    updated =
      if org_id in selected do
        List.delete(selected, org_id)
      else
        [org_id | selected]
      end

    {:noreply, assign(socket, :selected_org_ids, updated)}
  end

  # Deactivate/Reactivate handlers (same pattern as Show)
  def handle_event("request_deactivate", _params, socket) do
    {:noreply, assign(socket, :confirm_deactivate, true)}
  end

  def handle_event("cancel_deactivate", _params, socket) do
    {:noreply, assign(socket, :confirm_deactivate, false)}
  end

  def handle_event("confirm_deactivate", _params, socket) do
    current_account = socket.assigns.current_scope.account
    account = socket.assigns.account

    case Identity.deactivate_account(account, current_account) do
      {:ok, _account} ->
        account = Identity.get_account_with_orgs!(account.id)

        {:noreply,
         socket
         |> assign(:account, account)
         |> assign(:confirm_deactivate, false)
         |> put_flash(:info, "Account deactivated successfully.")}

      {:error, :cannot_deactivate_self} ->
        {:noreply,
         socket
         |> assign(:confirm_deactivate, false)
         |> put_flash(:error, "You cannot deactivate your own account.")}

      {:error, :last_admin} ->
        {:noreply,
         socket
         |> assign(:confirm_deactivate, false)
         |> put_flash(:error, "Cannot deactivate the last admin account.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:confirm_deactivate, false)
         |> put_flash(:error, "Failed to deactivate account.")}
    end
  end

  def handle_event("request_reactivate", _params, socket) do
    {:noreply, assign(socket, :confirm_reactivate, true)}
  end

  def handle_event("cancel_reactivate", _params, socket) do
    {:noreply, assign(socket, :confirm_reactivate, false)}
  end

  def handle_event("confirm_reactivate", _params, socket) do
    account = socket.assigns.account

    case Identity.reactivate_account(account) do
      {:ok, _account} ->
        account = Identity.get_account_with_orgs!(account.id)

        {:noreply,
         socket
         |> assign(:account, account)
         |> assign(:confirm_reactivate, false)
         |> put_flash(:info, "Account reactivated successfully.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:confirm_reactivate, false)
         |> put_flash(:error, "Failed to reactivate account.")}
    end
  end

  @impl true
  def handle_info({:avatar_processed, account}, socket) do
    {:noreply, assign(socket, :account, account)}
  end

  def handle_info({:avatar_failed, _account}, socket) do
    {:noreply, put_flash(socket, :error, "Avatar processing failed.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <:toolbar>
        <div class="max-w-7xl mx-auto flex items-center gap-4 px-4 sm:px-6 lg:px-8 py-3">
          <.link
            navigate={~p"/admin/accounts/#{@account.id}"}
            class="text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <h1 class="text-lg font-ds-heading font-bold text-ds-on-surface">Edit Account</h1>
        </div>
      </:toolbar>

      <div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <.form
          for={@form}
          id="account-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
          data-testid="account-form"
        >
          <.input field={@form[:name]} type="text" label="Full name" />
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input
            field={@form[:password]}
            type="password"
            label="New password"
            placeholder="Leave blank to keep current"
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            placeholder="Leave blank to keep current"
          />
          <.input
            field={@form[:role]}
            type="select"
            label="Role"
            options={[{"Viewer", :viewer}, {"Editor", :editor}, {"Admin", :admin}]}
            disabled={@account.id == @current_scope.account.id}
          />

          <%!-- Avatar upload --%>
          <div>
            <label class="block text-sm font-medium text-ds-on-surface mb-2">Avatar</label>
            <.live_file_input upload={@uploads.avatar} class="text-sm" data-testid="avatar-upload" />
            <div :for={entry <- @uploads.avatar.entries} class="mt-2">
              <.live_img_preview entry={entry} class="w-20 h-20 rounded-full object-cover" />
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="text-ds-error text-xs mt-1 hover:underline"
              >
                Remove
              </button>
              <p
                :for={err <- upload_errors(@uploads.avatar, entry)}
                class="text-ds-error text-xs mt-1"
              >
                {error_to_string(err)}
              </p>
            </div>
          </div>

          <%!-- Organization selection --%>
          <div>
            <label class="block text-sm font-medium text-ds-on-surface mb-2">Organizations</label>
            <div class="space-y-2" data-testid="org-selection">
              <label :for={org <- @organizations} class="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  name="organization_ids[]"
                  value={org.id}
                  checked={org.id in @selected_org_ids}
                  class="rounded border-ds-outline"
                />
                <span class="text-sm text-ds-on-surface">{org.name}</span>
              </label>
            </div>
          </div>

          <div class="flex gap-4">
            <button
              type="submit"
              class="rounded-ds-sharp bg-ds-primary px-6 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
              data-testid="account-submit-btn"
            >
              Save Changes
            </button>
            <.link
              navigate={~p"/admin/accounts/#{@account.id}"}
              class="rounded-ds-sharp px-6 py-2 text-sm font-ds-body text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
            >
              Cancel
            </.link>
          </div>
        </.form>

        <%!-- Deactivate/Reactivate section (hidden for own account) --%>
        <%= if @account.id != @current_scope.account.id do %>
          <div class="mt-8 pt-6 border-t border-ds-outline-variant/20">
            <%= if is_nil(@account.deactivated_at) do %>
              <button
                phx-click="request_deactivate"
                class="rounded-ds-sharp bg-ds-error px-4 py-2 text-sm font-ds-body font-medium text-ds-on-error hover:bg-ds-error/90 transition-colors"
                data-testid="account-deactivate-btn"
              >
                Deactivate Account
              </button>
            <% else %>
              <button
                phx-click="request_reactivate"
                class="rounded-ds-sharp bg-ds-primary px-4 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
                data-testid="account-reactivate-btn"
              >
                Reactivate Account
              </button>
            <% end %>
          </div>
        <% end %>
      </div>

      <%= if @confirm_deactivate do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
          data-testid="deactivate-modal"
        >
          <div class="bg-ds-surface-card rounded-ds-sharp p-6 max-w-sm mx-4 shadow-xl">
            <h3 class="text-lg font-ds-heading font-bold text-ds-on-surface mb-2">
              Deactivate Account
            </h3>
            <p class="text-sm text-ds-on-surface-variant mb-6">
              Are you sure you want to deactivate <strong>{@account.email}</strong>?
              They will be immediately logged out and unable to log in.
            </p>
            <div class="flex gap-3 justify-end">
              <button
                phx-click="cancel_deactivate"
                class="rounded-ds-sharp px-4 py-2 text-sm font-ds-body font-medium text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
                data-testid="deactivate-cancel-btn"
              >
                Cancel
              </button>
              <button
                phx-click="confirm_deactivate"
                class="rounded-ds-sharp bg-ds-error px-4 py-2 text-sm font-ds-body font-medium text-ds-on-error hover:bg-ds-error/90 transition-colors"
                data-testid="deactivate-confirm-btn"
              >
                Deactivate
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @confirm_reactivate do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
          data-testid="reactivate-modal"
        >
          <div class="bg-ds-surface-card rounded-ds-sharp p-6 max-w-sm mx-4 shadow-xl">
            <h3 class="text-lg font-ds-heading font-bold text-ds-on-surface mb-2">
              Reactivate Account
            </h3>
            <p class="text-sm text-ds-on-surface-variant mb-6">
              Are you sure you want to reactivate <strong>{@account.email}</strong>?
              They will be able to log in again.
            </p>
            <div class="flex gap-3 justify-end">
              <button
                phx-click="cancel_reactivate"
                class="rounded-ds-sharp px-4 py-2 text-sm font-ds-body font-medium text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
                data-testid="reactivate-cancel-btn"
              >
                Cancel
              </button>
              <button
                phx-click="confirm_reactivate"
                class="rounded-ds-sharp bg-ds-primary px-4 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
                data-testid="reactivate-confirm-btn"
              >
                Reactivate
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:too_many_files), do: "Only one avatar allowed"
  defp error_to_string(:not_accepted), do: "Invalid file type"
  defp error_to_string(err), do: inspect(err)
end
