defmodule EscalimetroWeb.ModerationLive.IndexTest do
  use EscalimetroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events.Vote
  alias Escalimetro.Repo

  setup :register_and_log_in_user

  test "user rejects and restores a vote", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
    participant = event_participant_fixture(scope, event)
    vote = vote_fixture(scope, event, participant, ballot)

    {:ok, view, _html} = live(conn, ~p"/events/#{event}/moderation")

    assert has_element?(view, "#moderation-votes-list")
    assert has_element?(view, "#vote-reject-button-#{vote.id}")

    view
    |> form("#vote-reject-form-#{vote.id}", vote: %{rejection_reason: "Duplicado"})
    |> render_submit()

    assert Repo.get!(Vote, vote.id).rejection_reason == "Duplicado"
    assert has_element?(view, "#vote-restore-button-#{vote.id}")

    view
    |> element("#vote-restore-button-#{vote.id}")
    |> render_click()

    assert is_nil(Repo.get!(Vote, vote.id).rejected_at)
    assert has_element?(view, "#vote-reject-button-#{vote.id}")
  end

  test "user cannot access moderation for another user's event", %{conn: conn} do
    event = event_fixture()

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/events/#{event}/moderation")

    assert path == ~p"/events"
    assert %{"error" => "Evento nao encontrado ou sem acesso."} = flash
  end
end
