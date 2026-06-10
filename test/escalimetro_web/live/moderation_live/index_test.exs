defmodule EscalimetroWeb.ModerationLive.IndexTest do
  use EscalimetroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events.{BallotOption, Vote}
  alias Escalimetro.Repo

  setup :register_and_log_in_user

  test "user sees votes as instantly computed without individual approval actions", %{
    conn: conn,
    scope: scope
  } do
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
    participant = event_participant_fixture(scope, event)
    vote = vote_fixture(scope, event, participant, ballot)

    {:ok, view, _html} = live(conn, ~p"/events/#{event}/moderation")

    assert has_element?(view, "#moderation-votes-list")
    assert has_element?(view, "#moderation-vote-#{vote.id}", "Ativo")
    assert has_element?(view, "#moderation-vote-immediate-note-#{vote.id}")
    refute has_element?(view, "#vote-reject-button-#{vote.id}")
    refute has_element?(view, "#vote-restore-button-#{vote.id}")
    assert is_nil(Repo.get!(Vote, vote.id).rejected_at)
  end

  test "user cannot access moderation for another user's event", %{conn: conn} do
    event = event_fixture()

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/events/#{event}/moderation")

    assert path == ~p"/events"
    assert %{"error" => "Evento nao encontrado ou sem acesso."} = flash
  end

  test "user rejects a suggested option and active votes for it", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event, %{allow_suggestion: true})
    participant = event_participant_fixture(scope, event)
    voter = event_participant_fixture(scope, event)

    assert {:ok, option} =
             Escalimetro.Events.suggest_option(participant, ballot, %{label: "Sugestao moderada"})

    assert {:ok, vote} =
             Escalimetro.Events.cast_vote(voter, ballot, %{ballot_option_id: option.id})

    {:ok, view, _html} = live(conn, ~p"/events/#{event}/moderation")

    assert has_element?(view, "#moderation-suggested-options-list")
    assert has_element?(view, "#suggestion-reject-button-#{option.id}")

    view
    |> element("#suggestion-reject-button-#{option.id}")
    |> render_click()

    assert Repo.get!(BallotOption, option.id).rejected_at
    assert Repo.get!(Vote, vote.id).rejected_at
  end
end
