defmodule AshStorage.ResourceTest do
  use ExUnit.Case, async: true

  alias AshStorage.Resource.Info

  describe "DSL introspection" do
    test "reads has_one attachments" do
      attachments = Info.has_one_attachments(AshStorage.Test.Post)
      assert length(attachments) == 1
      assert [att] = attachments
      assert att.name == :cover_image
      assert att.type == :one
    end

    test "reads has_many attachments" do
      attachments = Info.has_many_attachments(AshStorage.Test.Post)
      assert length(attachments) == 1
      assert [att] = attachments
      assert att.name == :documents
      assert att.type == :many
      assert att.dependent == :detach
    end

    test "reads all attachments" do
      attachments = Info.attachments(AshStorage.Test.Post)
      assert length(attachments) == 2
      names = Enum.map(attachments, & &1.name)
      assert :cover_image in names
      assert :documents in names
    end

    test "looks up attachment by name" do
      assert {:ok, att} = Info.attachment(AshStorage.Test.Post, :cover_image)
      assert att.name == :cover_image
      assert att.type == :one
    end

    test "returns error for unknown attachment" do
      assert :error = Info.attachment(AshStorage.Test.Post, :nonexistent)
    end

    test "reads default service from section" do
      assert {:ok, {AshStorage.Service.Test, []}} =
               Info.storage_service(AshStorage.Test.Post)
    end

    test "attachment defaults dependent to :purge" do
      {:ok, att} = Info.attachment(AshStorage.Test.Post, :cover_image)
      assert att.dependent == :purge
    end
  end
end
