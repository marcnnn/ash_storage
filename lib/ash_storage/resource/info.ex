defmodule AshStorage.Resource.Info do
  @moduledoc "Introspection helpers for `AshStorage.Resource`"
  use Spark.InfoGenerator, extension: AshStorage.Resource, sections: [:storage]

  @doc "All attachment definitions on the resource"
  def attachments(resource) do
    storage(resource)
  end

  @doc "All has_one_attached definitions on the resource"
  def has_one_attachments(resource) do
    resource |> attachments() |> Enum.filter(&(&1.type == :one))
  end

  @doc "All has_many_attached definitions on the resource"
  def has_many_attachments(resource) do
    resource |> attachments() |> Enum.filter(&(&1.type == :many))
  end

  @doc "Get a specific attachment by name"
  def attachment(resource, name) do
    case Enum.find(attachments(resource), &(&1.name == name)) do
      nil -> :error
      att -> {:ok, att}
    end
  end

  @doc "Get the effective service for an attachment (attachment-level overrides resource-level)"
  def service_for_attachment(resource, attachment) do
    attachment.service || storage_service(resource)
  end
end
