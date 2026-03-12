import Config

pg_url = System.get_env("PG_URL") || "postgres:postgres@127.0.0.1"
pg_database = System.get_env("PG_DATABASE") || "ash_storage_dev"

config :ash_storage, Demo.Repo,
  url: "ecto://#{pg_url}/#{pg_database}"

config :ash_storage,
  ecto_repos: [Demo.Repo]

config :ash_storage, :oban,
  repo: Demo.Repo,
  plugins: [{Oban.Plugins.Cron, []}],
  queues: [blob_purge_blob: 10, blob_run_pending_analyzers: 10]
