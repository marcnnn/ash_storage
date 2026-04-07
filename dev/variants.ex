defmodule Demo.Variants.Uppercase do
  @moduledoc false
  @behaviour AshStorage.Variant

  @impl true
  def accept?("text/" <> _), do: true
  def accept?(_), do: false

  @impl true
  def transform(source_path, dest_path, _opts) do
    content = File.read!(source_path)
    File.write!(dest_path, String.upcase(content))
    {:ok, %{content_type: "text/plain"}}
  end
end

defmodule Demo.Variants.Reversed do
  @moduledoc false
  @behaviour AshStorage.Variant

  @impl true
  def accept?("text/" <> _), do: true
  def accept?(_), do: false

  @impl true
  def transform(source_path, dest_path, _opts) do
    content = File.read!(source_path)
    File.write!(dest_path, String.reverse(content))
    {:ok, %{content_type: "text/plain"}}
  end
end

defmodule Demo.Variants.Excerpt do
  @moduledoc false
  @behaviour AshStorage.Variant

  @impl true
  def accept?("text/" <> _), do: true
  def accept?(_), do: false

  @impl true
  def transform(source_path, dest_path, opts) do
    max_chars = Keyword.get(opts, :max_chars, 100)
    content = File.read!(source_path)
    excerpt = String.slice(content, 0, max_chars)
    File.write!(dest_path, excerpt)
    {:ok, %{content_type: "text/plain"}}
  end
end
