defmodule Ancestry.Factory do
  use ExMachina.Ecto, repo: Ancestry.Repo

  alias Ancestry.StringUtils

  def organization_factory do
    %Ancestry.Organizations.Organization{
      name: sequence(:org_name, &"Organization #{&1}")
    }
  end

  def family_factory do
    %Ancestry.Families.Family{
      name: sequence(:family_name, &"Family #{&1}"),
      organization: build(:organization)
    }
  end

  def person_factory do
    %Ancestry.People.Person{
      given_name: sequence(:given_name, &"Person #{&1}"),
      surname: "Test",
      name_search: &person_name_search/1,
      organization: build(:organization)
    }
  end

  def acquaintance_factory do
    %Ancestry.People.Person{
      given_name: sequence(:given_name, &"Acquaintance #{&1}"),
      surname: "Test",
      name_search: &person_name_search/1,
      kind: "acquaintance",
      organization: build(:organization)
    }
  end

  defp person_name_search(%Ancestry.People.Person{} = p) do
    fields = [p.given_name, p.surname, p.given_name_at_birth, p.surname_at_birth, p.nickname]
    alt_names = p.alternate_names || []

    (fields ++ alt_names)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
    |> StringUtils.normalize()
  end

  def family_member_factory do
    %Ancestry.People.FamilyMember{
      family: build(:family),
      person: build(:person)
    }
  end

  def gallery_factory do
    %Ancestry.Galleries.Gallery{
      name: sequence(:gallery_name, &"Gallery #{&1}"),
      family: build(:family)
    }
  end

  def photo_factory do
    %Ancestry.Galleries.Photo{
      gallery: build(:gallery),
      original_path: "test/fixtures/test_image.jpg",
      original_filename: "test.jpg",
      content_type: "image/jpeg",
      status: "processed",
      file_hash: nil
    }
  end

  def photo_comment_factory do
    %Ancestry.Comments.PhotoComment{
      text: sequence(:comment_text, &"Comment #{&1}"),
      photo: build(:photo),
      account: build(:account)
    }
  end

  def account_factory do
    %Ancestry.Identity.Account{
      email: sequence(:account_email, &"account#{&1}@example.com"),
      confirmed_at: DateTime.utc_now(:second),
      role: :admin
    }
  end

  def unconfirmed_account_factory do
    %Ancestry.Identity.Account{
      email: sequence(:account_email, &"account#{&1}@example.com"),
      role: :admin
    }
  end

  def account_organization_factory do
    %Ancestry.Organizations.AccountOrganization{
      account: build(:account),
      organization: build(:organization)
    }
  end

  def vault_factory do
    %Ancestry.Memories.Vault{
      name: sequence(:vault_name, &"Vault #{&1}"),
      family: build(:family)
    }
  end

  def memory_factory do
    %Ancestry.Memories.Memory{
      name: sequence(:memory_name, &"Memory #{&1}"),
      content: "<div>A test memory</div>",
      description: "A test memory",
      memory_vault: build(:vault)
    }
  end

  def memory_mention_factory do
    %Ancestry.Memories.MemoryMention{
      memory: build(:memory),
      person: build(:person)
    }
  end

  def audit_log_factory do
    %Ancestry.Audit.Log{
      command_id: sequence(:audit_command_id, &"cmd-#{&1}-#{Ecto.UUID.generate()}"),
      correlation_ids: sequence(:audit_correlation_ids, &["req-#{&1}-#{Ecto.UUID.generate()}"]),
      command_module: "Ancestry.Commands.AddCommentToPhoto",
      account_id: sequence(:audit_account_id, & &1),
      account_name: "Tester",
      account_email: sequence(:audit_email, &"audit#{&1}@example.com"),
      organization_id: nil,
      organization_name: nil,
      payload: %{
        "arguments" => %{"photo_id" => 1, "text" => "hi"},
        "metadata" => %{}
      }
    }
  end
end
