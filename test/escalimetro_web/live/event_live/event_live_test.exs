defmodule EscalimetroWeb.EventLiveTest do
  use EscalimetroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Escalimetro.EventsFixtures

  alias Escalimetro.Repo
  alias Escalimetro.Events.Event
  alias Escalimetro.Events
  alias Escalimetro.Events.{Ballot, BallotOption, Vote}

  setup :register_and_log_in_user

  test "user creates an event", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/events/new")

    assert has_element?(view, "#event-form")
    title = unique_event_title()

    redirect =
      view
      |> form("#event-form", event: %{title: title, description: "Pauta geral"})
      |> render_submit()

    event = Repo.get_by!(Event, title: title)
    assert {:ok, _show, _html} = follow_redirect(redirect, conn, ~p"/events/#{event}")
  end

  test "user edits an event", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/events/#{event}/edit")

    assert has_element?(view, "#event-title-input")
    new_title = unique_event_title()

    redirect =
      view
      |> form("#event-form", event: %{title: new_title})
      |> render_submit()

    assert Repo.get!(Event, event.id).title == new_title
    assert {:ok, _show, _html} = follow_redirect(redirect, conn, ~p"/events/#{event}")
  end

  test "user cannot access another user's event", %{conn: conn} do
    other_event = event_fixture()

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/events/#{other_event}")

    assert path == ~p"/events"
    assert %{"error" => "Evento nao encontrado ou sem acesso."} = flash
  end

  test "user completes an event and open ballots close", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event)

    {:ok, view, _html} = live(conn, ~p"/events/#{event}")
    assert has_element?(view, "#event-complete-button")

    view
    |> element("#event-complete-button")
    |> render_click()

    assert Repo.get!(Event, event.id).status == "completed"
    assert Repo.get!(Ballot, ballot.id).status == "closed"
    refute has_element?(view, "#event-complete-button")
  end

  test "user creates ballots and options from event show", %{conn: conn, scope: scope} do
    event = event_fixture(scope)

    {:ok, view, _html} = live(conn, ~p"/events/#{event}")

    assert has_element?(view, "#ballot-form")

    view
    |> form("#ballot-form",
      ballot: %{
        title: "Escolher sabor",
        description: "Pizza principal",
        kind: "multiple_choice",
        allow_sugestion: "true"
      }
    )
    |> render_submit()

    ballot = Repo.get_by!(Ballot, event_id: event.id, title: "Escolher sabor")
    assert has_element?(view, "#ballot-#{ballot.id}")

    view
    |> form("#ballot-option-form-#{ballot.id}",
      ballot_id: ballot.id,
      option: %{label: "Calabresa"}
    )
    |> render_submit()

    assert Repo.get_by!(BallotOption, ballot_id: ballot.id, label: "Calabresa")
    assert has_element?(view, "#ballot-option-form-#{ballot.id}")
  end

  test "user reviews participants in arrival order and removes votes", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event)
    option = ballot_option_fixture(scope, ballot, %{label: "Calabresa"})
    first = event_participant_fixture(scope, event, %{display_name: "Primeiro"})
    second = event_participant_fixture(scope, event, %{display_name: "Segundo"})

    assert {:ok, vote} =
             Events.create_vote(scope, event, first, ballot, %{ballot_option_id: option.id})

    {:ok, view, _html} = live(conn, ~p"/events/#{event}")

    assert has_element?(view, "#participant-review-#{first.id}")
    assert has_element?(view, "#participant-review-#{second.id}")
    assert has_element?(view, "#participant-vote-checkbox-#{vote.id}")
    assert has_element?(view, "#participant-clear-votes-#{first.id}")

    view
    |> element("#participant-vote-checkbox-#{vote.id}")
    |> render_click()

    refute Repo.get(Vote, vote.id)
    refute has_element?(view, "#participant-vote-checkbox-#{vote.id}")
  end

  test "user removes all votes from one participant", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event)
    first_option = ballot_option_fixture(scope, ballot, %{label: "Calabresa"})
    second_option = ballot_option_fixture(scope, ballot, %{label: "Mussarela"})
    participant = event_participant_fixture(scope, event, %{display_name: "Primeiro"})

    assert {:ok, first_vote} =
             Events.create_vote(scope, event, participant, ballot, %{
               ballot_option_id: first_option.id
             })

    assert {:ok, second_vote} =
             Events.create_vote(scope, event, participant, ballot, %{
               ballot_option_id: second_option.id
             })

    {:ok, view, _html} = live(conn, ~p"/events/#{event}")

    assert has_element?(view, "#participant-clear-votes-#{participant.id}")

    view
    |> element("#participant-clear-votes-#{participant.id}")
    |> render_click()

    refute Repo.get(Vote, first_vote.id)
    refute Repo.get(Vote, second_vote.id)
    refute has_element?(view, "#participant-clear-votes-#{participant.id}")
  end

  test "completed event cannot be edited", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    {:ok, completed_event} = Escalimetro.Events.complete_event(scope, event)

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/events/#{completed_event}/edit")

    assert path == ~p"/events/#{completed_event}"
    assert %{"error" => "Eventos concluidos nao podem ser editados."} = flash
  end
end
