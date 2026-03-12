defmodule Demo.Analyzers.FileInfo do
  @moduledoc """
  Eager analyzer that extracts basic file info: line count for text files,
  byte entropy estimate, and detected file type.
  """
  @behaviour AshStorage.Analyzer

  @impl true
  def accept?(_content_type), do: true

  @impl true
  def analyze(path, _opts) do
    stat = File.stat!(path)
    data = File.read!(path)

    result = %{
      "file_size_bytes" => stat.size,
      "md5" => :crypto.hash(:md5, data) |> Base.encode16(case: :lower)
    }

    result =
      if String.printable?(data) do
        lines = data |> String.split("\n") |> length()
        words = data |> String.split(~r/\s+/, trim: true) |> length()
        Map.merge(result, %{"line_count" => lines, "word_count" => words})
      else
        result
      end

    {:ok, result}
  end
end

defmodule Demo.Analyzers.ImageDimensions do
  @moduledoc """
  Analyzer that extracts image dimensions from PNG and JPEG files
  by reading file headers directly (no external dependencies).
  """
  @behaviour AshStorage.Analyzer

  @impl true
  def accept?("image/png"), do: true
  def accept?("image/jpeg"), do: true
  def accept?("image/jpg"), do: true
  def accept?(_), do: false

  @impl true
  def analyze(path, _opts) do
    data = File.read!(path)

    case detect_dimensions(data) do
      {:ok, width, height} ->
        {:ok, %{"width" => width, "height" => height, "format" => detect_format(data)}}

      :error ->
        {:ok, %{"format" => "unknown"}}
    end
  end

  # PNG: bytes 16-23 contain width (4 bytes) and height (4 bytes) in the IHDR chunk
  defp detect_dimensions(<<0x89, 0x50, 0x4E, 0x47, _::binary-size(12), width::32, height::32, _::binary>>) do
    {:ok, width, height}
  end

  # JPEG: scan for SOF0 marker (0xFF 0xC0)
  defp detect_dimensions(<<0xFF, 0xD8, rest::binary>>) do
    find_jpeg_dimensions(rest)
  end

  defp detect_dimensions(_), do: :error

  defp find_jpeg_dimensions(<<0xFF, 0xC0, _length::16, _precision::8, height::16, width::16, _::binary>>) do
    {:ok, width, height}
  end

  defp find_jpeg_dimensions(<<0xFF, 0xC2, _length::16, _precision::8, height::16, width::16, _::binary>>) do
    {:ok, width, height}
  end

  defp find_jpeg_dimensions(<<0xFF, _marker::8, length::16, rest::binary>>) when byte_size(rest) >= length - 2 do
    <<_skip::binary-size(length - 2), remaining::binary>> = rest
    find_jpeg_dimensions(remaining)
  end

  defp find_jpeg_dimensions(<<_::8, rest::binary>>), do: find_jpeg_dimensions(rest)
  defp find_jpeg_dimensions(<<>>), do: :error

  defp detect_format(<<0x89, 0x50, 0x4E, 0x47, _::binary>>), do: "png"
  defp detect_format(<<0xFF, 0xD8, _::binary>>), do: "jpeg"
  defp detect_format(_), do: "unknown"
end
