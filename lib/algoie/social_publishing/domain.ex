defmodule Algoie.SocialPublishing.Domain do
  use Ash.Domain

  resources do
    resource(Algoie.SocialPublishing.SocialProfile)
    resource(Algoie.SocialPublishing.SocialAccount)
  end
end
