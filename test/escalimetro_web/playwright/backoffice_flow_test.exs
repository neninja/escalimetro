defmodule EscalimetroWeb.Playwright.BackofficeFlowTest do
  use PhoenixTest.Playwright.Case, async: false, browser_pool: false

  use EscalimetroWeb, :verified_routes

  import Escalimetro.AccountsFixtures
  import Escalimetro.EventsFixtures

  test "system admin reviews dashboard and impersonates a user", %{conn: conn} do
    admin = system_admin_fixture()
    target_user = user_fixture()
    target_scope = user_scope_fixture(target_user)
    target_event = event_fixture(target_scope, %{title: "Evento do usuario alvo", status: "open"})

    conn
    |> log_in_with_magic_link(admin)
    |> visit(~p"/backoffice")
    |> assert_has("#backoffice-dashboard")
    |> assert_has("#backoffice-active-users-count", text: "2")
    |> assert_has("#backoffice-open-events-count", text: "1")
    |> assert_has("#users-#{target_user.id}", text: target_user.email)
    |> click_button("#impersonate-user-button-#{target_user.id}", "Impersonar")
    |> assert_path(~p"/events", timeout: 5_000)
    |> assert_has("#flash-info", text: "Impersonando #{target_user.email}.")
    |> assert_has("#impersonation-banner", text: target_user.email)
    |> assert_has("#open-events", text: target_event.title)
    |> assert_has("#stop-impersonation-button")
    |> evaluate("document.querySelector('#stop-impersonation-button').click()")
    |> assert_path(~p"/backoffice", timeout: 5_000)
    |> assert_has("#flash-info", text: "Impersonacao encerrada.")
    |> refute_has("#impersonation-banner")
    |> assert_has("#backoffice-dashboard")
  end

  test "regular user is redirected away from backoffice", %{conn: conn} do
    user = user_fixture()

    conn
    |> log_in_with_magic_link(user)
    |> visit(~p"/backoffice")
    |> assert_path(~p"/events")
    |> assert_has("#flash-error", text: "Acesso restrito ao backoffice.")
  end

  defp log_in_with_magic_link(session, user) do
    {token, _hashed_token} = generate_user_magic_link_token(user)

    session
    |> visit(~p"/users/log-in/#{token}")
    |> assert_has("#login_form")
    |> click_button("Log me in only this time")
    |> assert_path(~p"/", timeout: 5_000)
  end
end
