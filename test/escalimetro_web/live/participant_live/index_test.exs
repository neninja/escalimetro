defmodule EscalimetroWeb.ParticipantLive.IndexTest do
  use EscalimetroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events.{EventParticipant, Vote}
  alias Escalimetro.Repo

  setup :register_and_log_in_user

  test "user invalidates a participant and active votes become rejected", %{
    conn: conn,
    scope: scope
  } do
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
    participant = event_participant_fixture(scope, event)
    vote = vote_fixture(scope, event, participant, ballot)

    {:ok, view, _html} = live(conn, ~p"/events/#{event}/participants")

    assert has_element?(view, "#participants-list")
    assert has_element?(view, "#participant-invalidate-button-#{participant.id}")

    view
    |> element("#participant-invalidate-button-#{participant.id}")
    |> render_click()

    assert Repo.get!(EventParticipant, participant.id).status == "invalidated"
    assert Repo.get!(Vote, vote.id).rejected_at
    refute has_element?(view, "#participant-invalidate-button-#{participant.id}")
  end

  test "user cannot access participants for another user's event", %{conn: conn} do
    event = event_fixture()

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/events/#{event}/participants")

    assert path == ~p"/events"
    assert %{"error" => "Evento nao encontrado ou sem acesso."} = flash
  end
end
