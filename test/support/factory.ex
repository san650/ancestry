defmodule Ancestry.Factory do
  use ExMachina.Ecto, repo: Ancestry.Repo

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
      organization: build(:organization)
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
      status: "processed"
    }
  end

  def account_factory do
    %Ancestry.Identity.Account{
      email: sequence(:account_email, &"account#{&1}@example.com"),
      confirmed_at: DateTime.utc_now(:second)
    }
  end

  def unconfirmed_account_factory do
    %Ancestry.Identity.Account{
      email: sequence(:account_email, &"account#{&1}@example.com")
    }
  end
end
