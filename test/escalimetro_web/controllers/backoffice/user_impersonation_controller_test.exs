defmodule EscalimetroWeb.Backoffice.UserImpersonationControllerTest do
  use EscalimetroWeb.ConnCase, async: false

  import Escalimetro.AccountsFixtures

  alias Escalimetro.Accounts

  test "system admin starts and stops impersonating a user", %{conn: conn} do
    admin = system_admin_fixture()
    target = user_fixture()

    conn =
      conn
      |> log_in_user(admin)
      |> post(~p"/backoffice/users/#{target}/impersonate")

    assert redirected_to(conn) == ~p"/events"
    assert get_session(conn, :impersonator_user_token)

    target_token = get_session(conn, :user_token)

    assert {%Accounts.User{id: target_id}, _token_inserted_at} =
             Accounts.get_user_by_session_token(target_token)

    assert target_id == target.id

    conn = delete(conn, ~p"/backoffice/impersonation")

    assert redirected_to(conn) == ~p"/backoffice"
    refute get_session(conn, :impersonator_user_token)

    restored_token = get_session(conn, :user_token)

    assert {%Accounts.User{id: admin_id}, _token_inserted_at} =
             Accounts.get_user_by_session_token(restored_token)

    assert admin_id == admin.id
  end

  test "regular user cannot impersonate", %{conn: conn} do
    user = user_fixture()
    target = user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> post(~p"/backoffice/users/#{target}/impersonate")

    assert redirected_to(conn) == ~p"/events"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Acesso restrito ao backoffice."
  end
end
