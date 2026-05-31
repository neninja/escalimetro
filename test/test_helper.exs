ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Escalimetro.Repo, :manual)
{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
Application.put_env(:phoenix_test, :base_url, EscalimetroWeb.Endpoint.url())
