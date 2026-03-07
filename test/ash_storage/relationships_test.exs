defmodule AshStorage.RelationshipsTest do
  use ExUnit.Case, async: false

  alias AshStorage.Operations

  setup do
    AshStorage.Service.Test.reset!()
    :ok
  end

  defp create_post!(title \\ "test post") do
    AshStorage.Test.Post
    |> Ash.Changeset.for_create(:create, %{title: title})
    |> Ash.create!()
  end

  describe "has_one_attached relationship" do
    test "loading cover_image returns nil when no attachment" do
      post = create_post!() |> Ash.load!(:cover_image)
      assert post.cover_image == nil
    end

    test "loading cover_image returns the attachment" do
      post = create_post!()
      {:ok, %{blob: _blob}} = Operations.attach(post, :cover_image, "img", filename: "photo.jpg")

      post = Ash.load!(post, :cover_image)
      assert post.cover_image != nil
      assert post.cover_image.name == "cover_image"
    end

    test "loading cover_image with nested blob" do
      post = create_post!()
      {:ok, %{blob: blob}} = Operations.attach(post, :cover_image, "img", filename: "photo.jpg")

      post = Ash.load!(post, cover_image: :blob)
      assert post.cover_image.blob.id == blob.id
      assert post.cover_image.blob.filename == "photo.jpg"
    end
  end

  describe "has_many_attached relationship" do
    test "loading documents returns empty list when no attachments" do
      post = create_post!() |> Ash.load!(:documents)
      assert post.documents == []
    end

    test "loading documents returns all attachments" do
      post = create_post!()
      {:ok, _} = Operations.attach(post, :documents, "doc1", filename: "a.txt")
      {:ok, _} = Operations.attach(post, :documents, "doc2", filename: "b.txt")

      post = Ash.load!(post, :documents)
      assert length(post.documents) == 2
      assert Enum.all?(post.documents, &(&1.name == "documents"))
    end

    test "loading documents with nested blobs" do
      post = create_post!()
      {:ok, %{blob: blob1}} = Operations.attach(post, :documents, "doc1", filename: "a.txt")
      {:ok, %{blob: blob2}} = Operations.attach(post, :documents, "doc2", filename: "b.txt")

      post = Ash.load!(post, documents: :blob)
      blob_ids = Enum.map(post.documents, & &1.blob.id) |> Enum.sort()
      assert blob_ids == Enum.sort([blob1.id, blob2.id])
    end
  end

  describe "cover_image_url calculation" do
    test "returns nil when no attachment" do
      post = create_post!() |> Ash.load!(:cover_image_url)
      assert post.cover_image_url == nil
    end

    test "returns the URL from the service" do
      post = create_post!()

      {:ok, %{blob: blob}} =
        Operations.attach(post, :cover_image, "img", filename: "photo.jpg")

      post = Ash.load!(post, :cover_image_url)
      assert post.cover_image_url == "http://test.local/storage/#{blob.key}"
    end
  end

  describe "relationship filtering" do
    test "cover_image and documents don't leak into each other" do
      post = create_post!()
      {:ok, _} = Operations.attach(post, :cover_image, "img", filename: "photo.jpg")
      {:ok, _} = Operations.attach(post, :documents, "doc", filename: "a.txt")

      post = Ash.load!(post, [:cover_image, :documents])
      assert post.cover_image.name == "cover_image"
      assert length(post.documents) == 1
      assert hd(post.documents).name == "documents"
    end
  end
end
