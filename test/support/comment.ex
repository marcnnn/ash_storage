defmodule AshStorage.Test.Comment do
  @moduledoc false
  use Ash.Resource,
    domain: AshStorage.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: [:body]]
  end
end
