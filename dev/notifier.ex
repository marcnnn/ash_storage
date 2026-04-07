defmodule Demo.BlobNotifier do
  @moduledoc false
  use Ash.Notifier

  @impl true
  def notify(%Ash.Notifier.Notification{action: %{name: :run_pending_analyzers}} = notification) do
    if Code.ensure_loaded?(Phoenix.PubSub) do
      Phoenix.PubSub.broadcast(
        Demo.PubSub,
        "blob_analysis",
        {:analysis_complete, notification.data}
      )
    else
      :ok
    end
  end

  def notify(_), do: :ok
end
