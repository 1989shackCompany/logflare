defmodule Logflare.LocalRepo.Sync do
  @moduledoc """
  Synchronized Repo data with LocalRepo data for
  """
  use Logflare.Commons
  use GenServer
  alias Logflare.EctoSchemaReflection
  alias Logflare.Changefeeds
  alias Logflare.Changefeeds.ChangefeedSubscription
  import Ecto.Query, warn: false
  require Logger

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  def start_link(args \\ %{}, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init(init_arg) do
    validate_all_triggers_exist()
    validate_all_changefeed_changesets_exists()
    sync_all_changefeed_tables()
    {:ok, init_arg}
  end

  def validate_all_changefeed_changesets_exists() do
    for %{schema: schema} <- Changefeeds.list_changefeed_subscriptions() do
      unless EctoSchemaReflection.changefeed_changeset_exists?(schema) do
        throw("Error: #{schema} doesn't implement changefeed_changeset")
      end
    end
  end

  def validate_all_triggers_exist() do
    in_db_triggers =
      from("triggers")
      |> where([t], t.event_object_schema == "public" and t.trigger_schema == "public")
      |> select(
        [t],
        %{
          table_name: t.event_object_table,
          trigger_name: t.trigger_name,
          event:
            fragment("string_agg(?, ',' ORDER BY ?)", t.event_manipulation, t.event_manipulation),
          timing: t.action_timing,
          definition: t.action_statement
        }
      )
      |> group_by([t], [1, 2, 4, 5])
      |> Repo.all(prefix: "information_schema")

    events = "DELETE,INSERT,UPDATE"
    timing = "AFTER"

    expected =
      Changefeeds.list_changefeed_subscriptions()
      |> Enum.map(fn
        %ChangefeedSubscription{table: table, id_only: id_only} = chgsub ->
          definition =
            if id_only do
              "EXECUTE FUNCTION changefeed_id_only_notify()"
            else
              "EXECUTE FUNCTION changefeed_notify()"
            end

          %{
            :definition => definition,
            :event => events,
            :table_name => table,
            :timing => timing,
            :trigger_name => Changefeeds.trigger_name(chgsub)
          }
      end)

    compared = expected -- in_db_triggers

    unless Enum.empty?(compared) do
      compared_string =
        for %{table_name: table, trigger_name: trigger_name} <- compared,
            do: "#{trigger_name} for #{table} table \n"

      Logger.error("""
      The following triggers don't exist or their definition doesn't match the expected:

      #{compared_string}
      """)

      throw("Some changefeed triggers do not exit!")
    end
  end

  def sync_all_changefeed_tables() do
    for chgf <- Changefeeds.list_changefeed_subscriptions() do
      sync_table(chgf)
    end
  end

  def sync_table(%ChangefeedSubscription{schema: schema}) do
    for x <- Repo.all(schema) |> Changefeeds.replace_assocs_with_nils(schema) do
      {:ok, struct} = LocalRepo.insert(x)

      :ok = Changefeeds.maybe_insert_virtual(struct)
    end

    Logger.debug("Synced memory repo for #{schema} schema")

    :ok
  end
end