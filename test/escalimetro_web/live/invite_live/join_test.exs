defmodule EscalimetroWeb.InviteLive.JoinTest do
  use EscalimetroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Escalimetro.AccountsFixtures
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events
  alias Escalimetro.Events.EventParticipant
  alias Escalimetro.Repo

  test "guest identifies with display name and enters voting", %{conn: conn} do
    scope = user_scope_fixture()
    event = event_fixture(scope)
    assert {:ok, invite} = Events.rotate_event_invite(scope, event)

    {:ok, view, _html} = live(conn, ~p"/join/#{invite.token}")

    assert has_element?(view, "#guest-identification-form")
    assert has_element?(view, "#guest-display-name-input")
    assert has_element?(view, "#guest-enter-event-button")

    redirect =
      view
      |> form("#guest-identification-form", guest: %{display_name: "Ana"})
      |> render_submit()

    participant = Repo.get_by!(EventParticipant, event_id: event.id, display_name: "Ana")
    assert participant.kind == "guest"

    assert {:ok, _view, _html} =
             follow_redirect(redirect, conn, ~p"/events/public/#{participant.participant_token}")
  end

  test "invalid invite token shows friendly state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/join/invalid-token")

    assert has_element?(view, "#invite-invalid-state")
  end

  test "invite invalidated after page open blocks guest entry", %{conn: conn} do
    scope = user_scope_fixture()
    event = event_fixture(scope)
    assert {:ok, invite} = Events.rotate_event_invite(scope, event)

    {:ok, view, _html} = live(conn, ~p"/join/#{invite.token}")
    assert {:ok, _invite} = Events.invalidate_event_invite(scope, event)

    view
    |> form("#guest-identification-form", guest: %{display_name: "Ana"})
    |> render_submit()

    assert has_element?(view, "#invite-invalid-state")
    refute Repo.get_by(EventParticipant, event_id: event.id, display_name: "Ana")
  end

  test "authenticated user enters without guest identification", %{conn: conn} do
    owner_scope = user_scope_fixture()
    event = event_fixture(owner_scope)
    assert {:ok, invite} = Events.rotate_event_invite(owner_scope, event)

    user = user_fixture()
    conn = log_in_user(conn, user)

    assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/join/#{invite.token}")

    participant = Repo.get_by!(EventParticipant, event_id: event.id, user_id: user.id)

    assert participant.kind == "user"
    assert path == ~p"/events/public/#{participant.participant_token}"
  end
end
