defmodule AshStorage.DirectUploadTest do
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

  describe "prepare_direct_upload/3" do
    test "creates blob and returns upload info" do
      {:ok, result} =
        Operations.prepare_direct_upload(AshStorage.Test.Post, :cover_image,
          filename: "photo.jpg",
          content_type: "image/jpeg",
          byte_size: 12_345
        )

      assert result.blob.filename == "photo.jpg"
      assert result.blob.content_type == "image/jpeg"
      assert result.blob.byte_size == 12_345
      assert result.blob.service_name == AshStorage.Service.Test

      assert result.url =~ "http://test.local/storage/direct/"
      assert result.method == :put
    end

    test "generates a unique key for each upload" do
      {:ok, result1} =
        Operations.prepare_direct_upload(AshStorage.Test.Post, :cover_image, filename: "a.jpg")

      {:ok, result2} =
        Operations.prepare_direct_upload(AshStorage.Test.Post, :cover_image, filename: "b.jpg")

      refute result1.blob.key == result2.blob.key
    end

    test "stores metadata on blob" do
      {:ok, result} =
        Operations.prepare_direct_upload(AshStorage.Test.Post, :cover_image,
          filename: "photo.jpg",
          metadata: %{"width" => 800, "height" => 600}
        )

      assert result.blob.metadata == %{"width" => 800, "height" => 600}
    end

    test "returns error for unknown attachment" do
      assert :error =
               Operations.prepare_direct_upload(AshStorage.Test.Post, :nonexistent,
                 filename: "f.txt"
               )
    end
  end

  describe "confirm_direct_upload/4" do
    test "attaches blob to record for has_one" do
      post = create_post!()

      {:ok, %{blob: blob}} =
        Operations.prepare_direct_upload(AshStorage.Test.Post, :cover_image,
          filename: "photo.jpg",
          content_type: "image/jpeg",
          byte_size: 100
        )

      # Simulate client uploading directly
      AshStorage.Service.Test.upload(
        blob.key,
        "direct upload data",
        AshStorage.Service.Context.new([])
      )

      {:ok, %{blob: confirmed_blob, attachment: attachment}} =
        Operations.confirm_direct_upload(post, :cover_image, blob.id)

      assert confirmed_blob.id == blob.id
      assert attachment.blob_id == blob.id

      # Verify via Ash.load!
      post = Ash.load!(post, cover_image: :blob)
      assert post.cover_image.blob.filename == "photo.jpg"
    end

    test "replaces existing has_one attachment" do
      post = create_post!()

      # First: attach normally
      {:ok, %{blob: old_blob}} =
        Operations.attach(post, :cover_image, "old data",
          filename: "old.jpg",
          content_type: "image/jpeg"
        )

      # Second: prepare and confirm direct upload
      {:ok, %{blob: new_blob}} =
        Operations.prepare_direct_upload(AshStorage.Test.Post, :cover_image,
          filename: "new.jpg",
          content_type: "image/jpeg",
          byte_size: 200
        )

      AshStorage.Service.Test.upload(
        new_blob.key,
        "new direct data",
        AshStorage.Service.Context.new([])
      )

      {:ok, _} = Operations.confirm_direct_upload(post, :cover_image, new_blob.id)

      # Old file should be purged
      refute AshStorage.Service.Test.exists?(old_blob.key)

      # New attachment in place
      post = Ash.load!(post, cover_image: :blob)
      assert post.cover_image.blob.filename == "new.jpg"
    end

    test "appends to has_many" do
      post = create_post!()

      {:ok, %{blob: blob1}} =
        Operations.prepare_direct_upload(AshStorage.Test.Post, :documents,
          filename: "doc1.pdf",
          byte_size: 100
        )

      {:ok, %{blob: blob2}} =
        Operations.prepare_direct_upload(AshStorage.Test.Post, :documents,
          filename: "doc2.pdf",
          byte_size: 200
        )

      # Simulate uploads
      ctx = AshStorage.Service.Context.new([])
      AshStorage.Service.Test.upload(blob1.key, "pdf1", ctx)
      AshStorage.Service.Test.upload(blob2.key, "pdf2", ctx)

      {:ok, _} = Operations.confirm_direct_upload(post, :documents, blob1.id)
      {:ok, _} = Operations.confirm_direct_upload(post, :documents, blob2.id)

      post = Ash.load!(post, documents: :blob)
      filenames = Enum.map(post.documents, & &1.blob.filename) |> Enum.sort()
      assert filenames == ["doc1.pdf", "doc2.pdf"]
    end

    test "returns error for nonexistent blob" do
      post = create_post!()

      assert {:error, :blob_not_found} =
               Operations.confirm_direct_upload(
                 post,
                 :cover_image,
                 Ash.UUID.generate()
               )
    end
  end
end
