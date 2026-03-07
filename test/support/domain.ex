defmodule AshStorage.Test.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource AshStorage.Test.Post
  end
end
