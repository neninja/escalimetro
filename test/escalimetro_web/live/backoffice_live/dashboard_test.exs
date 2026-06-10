defmodule EscalimetroWeb.BackofficeLive.DashboardTest do
  use EscalimetroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Escalimetro.AccountsFixtures
  import Escalimetro.EventsFixtures

  setup %{conn: conn} do
    admin = system_admin_fixture()
    scope = user_scope_fixture(admin)

    %{conn: log_in_user(conn, admin), user: admin, scope: scope}
  end

  test "system admin sees dashboard metrics and users", %{conn: conn, scope: scope} do
    target = user_fixture()
    _open_event = event_fixture(scope, %{status: "open"})

    {:ok, view, _html} = live(conn, ~p"/backoffice")

    assert has_element?(view, "#backoffice-dashboard")
    assert has_element?(view, "#backoffice-active-users-count", "2")
    assert has_element?(view, "#backoffice-open-events-count", "1")
    assert has_element?(view, "#backoffice-users-list")
    assert has_element?(view, "#users-#{target.id}", target.email)
    assert has_element?(view, "#impersonate-user-form-#{target.id}")
  end

  test "regular authenticated user is redirected away", %{conn: conn} do
    regular_user = user_fixture()
    conn = log_in_user(conn, regular_user)

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} = live(conn, ~p"/backoffice")

    assert path == ~p"/events"
    assert %{"error" => "Acesso restrito ao backoffice."} = flash
  end
end
