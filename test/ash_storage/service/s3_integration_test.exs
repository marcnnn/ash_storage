defmodule AshStorage.Service.S3IntegrationTest do
  @moduledoc """
  Integration tests for AshStorage.Service.S3 against a real MinIO instance.

  These tests start a MinIO container via Docker, run the tests, and clean up.
  Requires Docker to be available. Tagged with :s3_integration so they can be
  excluded from normal test runs.
  """
  use ExUnit.Case, async: false

  alias AshStorage.Service.Context
  alias AshStorage.Service.S3

  @moduletag :s3_integration

  @bucket "ash-storage-test"
  @port 19_000
  @container_name "ash_storage_minio_test"

  @service_opts [
    bucket: @bucket,
    region: "us-east-1",
    access_key_id: "minioadmin",
    secret_access_key: "minioadmin",
    endpoint_url: "http://localhost:#{@port}"
  ]

  setup_all do
    # Stop any leftover container from a previous run
    System.cmd("docker", ["rm", "-f", @container_name], stderr_to_stdout: true)

    # Start MinIO
    {_, 0} =
      System.cmd("docker", [
        "run",
        "-d",
        "--name",
        @container_name,
        "-p",
        "#{@port}:9000",
        "-e",
        "MINIO_ROOT_USER=minioadmin",
        "-e",
        "MINIO_ROOT_PASSWORD=minioadmin",
        "minio/minio",
        "server",
        "/data"
      ])

    # Wait for MinIO to be ready
    :ok = wait_for_minio(30)

    # Create the test bucket
    :ok = create_bucket()

    on_exit(fn ->
      System.cmd("docker", ["rm", "-f", @container_name], stderr_to_stdout: true)
    end)

    :ok
  end

  defp ctx(extra_opts \\ []) do
    Context.new(Keyword.merge(@service_opts, extra_opts))
  end

  describe "upload/3 and download/2" do
    test "round-trips binary data" do
      key = unique_key()
      assert :ok = S3.upload(key, "hello s3", ctx())
      assert {:ok, "hello s3"} = S3.download(key, ctx())
    end

    test "round-trips iolist data" do
      key = unique_key()
      assert :ok = S3.upload(key, ["hello", " ", "s3"], ctx())
      assert {:ok, "hello s3"} = S3.download(key, ctx())
    end

    test "round-trips binary data (large)" do
      key = unique_key()
      data = :crypto.strong_rand_bytes(1024 * 100)
      assert :ok = S3.upload(key, data, ctx())
      assert {:ok, ^data} = S3.download(key, ctx())
    end

    test "download returns not_found for missing key" do
      assert {:error, :not_found} = S3.download(unique_key(), ctx())
    end
  end

  describe "exists?/2" do
    test "returns true for existing key" do
      key = unique_key()
      S3.upload(key, "data", ctx())
      assert {:ok, true} = S3.exists?(key, ctx())
    end

    test "returns false for missing key" do
      assert {:ok, false} = S3.exists?(unique_key(), ctx())
    end
  end

  describe "delete/2" do
    test "deletes an existing object" do
      key = unique_key()
      S3.upload(key, "data", ctx())
      assert {:ok, true} = S3.exists?(key, ctx())

      assert :ok = S3.delete(key, ctx())
      assert {:ok, false} = S3.exists?(key, ctx())
    end

    test "succeeds for missing key" do
      assert :ok = S3.delete(unique_key(), ctx())
    end
  end

  describe "url/2" do
    test "generates a public URL" do
      key = unique_key()
      url = S3.url(key, ctx())
      assert url == "http://localhost:#{@port}/#{@bucket}/#{key}"
    end

    test "generates a presigned URL that works" do
      key = unique_key()
      S3.upload(key, "presigned content", ctx())

      url = S3.url(key, ctx(presigned: true))
      assert url =~ "X-Amz-Signature"

      # Actually fetch via the presigned URL
      assert {:ok, %{status: 200, body: "presigned content"}} = Req.get(url)
    end
  end

  describe "prefix option" do
    test "prefixes keys in storage" do
      key = unique_key()
      prefixed_ctx = ctx(prefix: "uploads/")

      assert :ok = S3.upload(key, "prefixed data", prefixed_ctx)
      assert {:ok, "prefixed data"} = S3.download(key, prefixed_ctx)

      # The actual S3 key should be prefixed
      assert {:ok, "prefixed data"} =
               S3.download("uploads/#{key}", ctx())
    end
  end

  describe "end-to-end with Operations" do
    setup do
      AshStorage.Service.Test.reset!()
      :ok
    end

    test "attach and load via S3" do
      # ConfigurablePost has otp_app: :ash_storage, so config overrides work
      Application.put_env(:ash_storage, AshStorage.Test.ConfigurablePost,
        storage: [
          service: {AshStorage.Service.S3, @service_opts}
        ]
      )

      post =
        AshStorage.Test.ConfigurablePost
        |> Ash.Changeset.for_create(:create, %{title: "s3 post"})
        |> Ash.create!()

      {:ok, %{blob: blob}} =
        AshStorage.Operations.attach(post, :avatar, "s3 file content",
          filename: "s3test.txt",
          content_type: "text/plain"
        )

      assert blob.filename == "s3test.txt"
      assert blob.service_name == AshStorage.Service.S3

      # Verify file is actually in S3
      assert {:ok, "s3 file content"} = S3.download(blob.key, ctx())

      # Load the attachment via Ash
      post = Ash.load!(post, avatar: :blob)
      assert post.avatar.blob.key == blob.key

      # Purge should remove from S3
      {:ok, _} = AshStorage.Operations.purge(post, :avatar)
      assert {:ok, false} = S3.exists?(blob.key, ctx())
    after
      Application.delete_env(:ash_storage, AshStorage.Test.ConfigurablePost)
    end

    test "direct upload flow via S3" do
      Application.put_env(:ash_storage, AshStorage.Test.ConfigurablePost,
        storage: [
          service: {AshStorage.Service.S3, @service_opts}
        ]
      )

      # Step 1: Prepare direct upload — creates blob, gets presigned URL
      {:ok, %{blob: blob, url: upload_url, method: :put}} =
        AshStorage.Operations.prepare_direct_upload(
          AshStorage.Test.ConfigurablePost,
          :avatar,
          filename: "direct.txt",
          content_type: "text/plain",
          byte_size: 14
        )

      assert blob.filename == "direct.txt"
      assert blob.service_name == AshStorage.Service.S3
      assert upload_url != nil

      # Step 2: Client uploads directly to S3 using presigned PUT URL
      assert {:ok, %{status: status}} = Req.put(upload_url, body: "direct content")
      assert status in [200, 204]

      # Step 3: Confirm the upload and attach to record
      post =
        AshStorage.Test.ConfigurablePost
        |> Ash.Changeset.for_create(:create, %{title: "direct upload post"})
        |> Ash.create!()

      {:ok, %{blob: confirmed_blob, attachment: attachment}} =
        AshStorage.Operations.confirm_direct_upload(post, :avatar, blob.id)

      assert confirmed_blob.id == blob.id
      assert attachment.blob_id == blob.id

      # Verify file is actually in S3
      assert {:ok, "direct content"} = S3.download(blob.key, ctx())

      # Verify loadable via Ash
      post = Ash.load!(post, avatar: :blob)
      assert post.avatar.blob.filename == "direct.txt"
    after
      Application.delete_env(:ash_storage, AshStorage.Test.ConfigurablePost)
    end
  end

  # -- Helpers --

  defp unique_key do
    "test/#{System.unique_integer([:positive])}-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  defp wait_for_minio(0), do: {:error, :timeout}

  defp wait_for_minio(attempts) do
    case Req.get("http://localhost:#{@port}/minio/health/ready") do
      {:ok, %{status: 200}} ->
        :ok

      _ ->
        Process.sleep(1000)
        wait_for_minio(attempts - 1)
    end
  end

  defp create_bucket do
    sigv4_opts = [
      service: :s3,
      region: "us-east-1",
      access_key_id: "minioadmin",
      secret_access_key: "minioadmin"
    ]

    case Req.put("http://localhost:#{@port}/#{@bucket}",
           aws_sigv4: sigv4_opts,
           body: ""
         ) do
      {:ok, %{status: status}} when status in [200, 409] -> :ok
      other -> {:error, other}
    end
  end
end
