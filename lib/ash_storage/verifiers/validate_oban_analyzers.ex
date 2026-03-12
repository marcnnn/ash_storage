defmodule AshStorage.Verifiers.ValidateObanAnalyzers do
  @moduledoc false
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    has_oban_analyzers? =
      (AshStorage.Info.has_one_attachments(dsl_state) ++
         AshStorage.Info.has_many_attachments(dsl_state))
      |> Enum.any?(fn attachment_def ->
        attachment_def.analyzers
        |> AshStorage.AttachmentDefinition.normalize_analyzers()
        |> Enum.any?(fn {_module, analyze, _opts} -> analyze == :oban end)
      end)

    if has_oban_analyzers? do
      blob_resource = AshStorage.Info.storage_blob_resource!(dsl_state)
      validate_blob_has_trigger(blob_resource)
    else
      :ok
    end
  end

  defp validate_blob_has_trigger(blob_resource) do
    if Code.ensure_loaded?(AshOban.Info) do
      case AshOban.Info.oban_triggers(blob_resource) do
        triggers when is_list(triggers) ->
          if Enum.any?(triggers, &(&1.action == :run_pending_analyzers)) do
            :ok
          else
            {:error,
             Spark.Error.DslError.exception(
               message: """
               One or more analyzers use `analyze: :oban`, but the blob resource \
               `#{inspect(blob_resource)}` does not have an AshOban trigger targeting \
               the `:run_pending_analyzers` action.

               Add an oban trigger to your blob resource:

                   oban do
                     triggers do
                       trigger :run_pending_analyzers do
                         action :run_pending_analyzers
                         read_action :read
                         where expr(...)
                         scheduler_cron("* * * * *")
                       end
                     end
                   end
               """
             )}
          end

        _ ->
          {:error,
           Spark.Error.DslError.exception(
             message: """
             One or more analyzers use `analyze: :oban`, but the blob resource \
             `#{inspect(blob_resource)}` does not use the `AshOban` extension.

             Add `AshOban` to your blob resource's extensions and configure a trigger \
             for the `:run_pending_analyzers` action.
             """
           )}
      end
    else
      {:error,
       Spark.Error.DslError.exception(
         message: """
         One or more analyzers use `analyze: :oban`, but `ash_oban` is not available. \
         Add `{:ash_oban, "~> 0.7"}` to your dependencies.
         """
       )}
    end
  end
end
