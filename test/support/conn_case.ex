defmodule LogflareWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common datastructures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  @session Plug.Session.init(
             store: :cookie,
             key: "_app",
             encryption_salt: "yadayada",
             signing_salt: "yadayada"
           )

  use ExUnit.CaseTemplate

  using _opts do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import LogflareWeb.Router.Helpers
      alias LogflareWeb.Router.Helpers, as: Routes
      import Logflare.Factory
      import Phoenix.LiveViewTest
      use Mimic

      # The default endpoint for testing
      @endpoint LogflareWeb.Endpoint

      setup context do
        Mimic.verify_on_exit!(context)
      end
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Logflare.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Logflare.Repo, {:shared, self()})
      # for global Mimic mocs
      Mimic.set_mimic_global(tags)
    end

    {:ok,
     conn:
       Phoenix.ConnTest.build_conn()
       |> Plug.Session.call(@session)
       |> Plug.Conn.fetch_session()}
  end
end
