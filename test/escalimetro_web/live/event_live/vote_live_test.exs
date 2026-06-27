defmodule EscalimetroWeb.EventLiveVoteTest do
  use EscalimetroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Escalimetro.AccountsFixtures
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events.{EventParticipant, Vote}
  alias Escalimetro.Events
  alias Escalimetro.Repo

  describe "logged in user" do
    setup :register_and_log_in_user

    test "does not need to identify with a display name", %{conn: conn, user: user} do
      scope = user_scope_fixture()
      event = event_fixture(scope, %{status: "open"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.public_invite_id}/vote")

      assert has_element?(view, "#voting-area")
      refute has_element?(view, "#participant-form")

      assert Repo.get_by!(EventParticipant, event_id: event.id, user_id: user.id, kind: "user")
    end
  end

  test "guest identifies and votes on a public event link", %{conn: conn} do
    scope = user_scope_fixture()
    event = event_fixture(scope, %{status: "open"})
    ballot = ballot_fixture(scope, event)
    option = ballot_option_fixture(scope, ballot, %{label: "Calabresa"})

    {:ok, view, _html} = live(conn, ~p"/events/#{event.public_invite_id}/vote")

    assert has_element?(view, "#participant-form")

    assert has_element?(
             view,
             "#guest-participant-session[data-public-invite-id='#{event.public_invite_id}']"
           )

    view
    |> form("#participant-form", participant: %{display_name: "Neni"})
    |> render_submit()

    public_invite_id = event.public_invite_id

    assert_push_event(view, "store_guest_participant", %{
      public_invite_id: ^public_invite_id,
      token: _token,
      display_name: "Neni"
    })

    participant = Repo.get_by!(EventParticipant, event_id: event.id, display_name: "Neni")
    assert has_element?(view, "#voting-area")

    view
    |> element("#vote-option-checkbox-#{option.id}")
    |> render_click()

    vote =
      Repo.get_by!(Vote,
        event_id: event.id,
        ballot_id: ballot.id,
        participant_id: participant.id,
        ballot_option_id: option.id
      )

    assert is_nil(vote.justification)
  end

  test "guest participant is restored from browser token", %{conn: conn} do
    scope = user_scope_fixture()
    event = event_fixture(scope, %{status: "open"})

    {:ok, participant} =
      Events.create_guest_participant(event, %{display_name: "Neni", kind: "guest"})

    token =
      Phoenix.Token.sign(
        EscalimetroWeb.Endpoint,
        "guest participant",
        {event.id, participant.id}
      )

    {:ok, view, _html} = live(conn, ~p"/events/#{event.public_invite_id}/vote")

    assert has_element?(view, "#participant-form")

    view
    |> element("#guest-participant-session")
    |> render_hook("restore_participant", %{token: token})

    assert has_element?(view, "#voting-area")
    refute has_element?(view, "#participant-form")
  end

  test "guest toggles yes no maybe vote by checkbox", %{conn: conn} do
    scope = user_scope_fixture()
    event = event_fixture(scope, %{status: "open"})
    ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})

    {:ok, view, _html} = live(conn, ~p"/events/#{event.public_invite_id}/vote")

    view
    |> form("#participant-form", participant: %{display_name: "Neni"})
    |> render_submit()

    participant = Repo.get_by!(EventParticipant, event_id: event.id, display_name: "Neni")

    view
    |> element("#vote-value-checkbox-#{ballot.id}-yes")
    |> render_click()

    assert Repo.get_by!(Vote,
             event_id: event.id,
             ballot_id: ballot.id,
             participant_id: participant.id,
             value: "yes"
           )
  end
end
