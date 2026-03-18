defmodule Ancestry.Factory do
  use ExMachina.Ecto, repo: Ancestry.Repo

  def family_factory do
    %Ancestry.Families.Family{
      name: sequence(:family_name, &"Family #{&1}")
    }
  end

  def person_factory do
    %Ancestry.People.Person{
      given_name: sequence(:given_name, &"Person #{&1}"),
      surname: "Test"
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
end
