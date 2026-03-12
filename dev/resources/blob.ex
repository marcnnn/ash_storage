defmodule Demo.Blob do
  @moduledoc false
  use Ash.Resource,
    domain: Demo.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.BlobResource, AshOban],
    notifiers: [Demo.BlobNotifier]

  postgres do
    table "storage_blobs"
    repo(Demo.Repo)
  end

  blob do
  end

  oban do
    triggers do
      trigger :purge_blob do
        action :purge_blob
        read_action :read
        where expr(pending_purge == true)
        scheduler_cron("* * * * *")
        max_attempts(3)
        scheduler_module_name(Demo.Blob.PurgeBlobScheduler)
        worker_module_name(Demo.Blob.PurgeBlobWorker)
      end

      trigger :run_pending_analyzers do
        action :run_pending_analyzers
        read_action :read

        where expr(
                fragment("EXISTS (SELECT 1 FROM jsonb_each(?) AS a WHERE a.value->>'status' = 'pending')", analyzers)
              )

        scheduler_cron("* * * * *")
        max_attempts(3)
        scheduler_module_name(Demo.Blob.RunPendingAnalyzersScheduler)
        worker_module_name(Demo.Blob.RunPendingAnalyzersWorker)
      end
    end
  end

  attributes do
    uuid_primary_key :id
  end
end
