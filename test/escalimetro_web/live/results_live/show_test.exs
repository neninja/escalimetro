defmodule EscalimetroWeb.ResultsLive.ShowTest do
  use EscalimetroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events
  alias Escalimetro.Events.Vote

  setup :register_and_log_in_user

  test "user sees consolidated ballot results and generates a summary", %{
    conn: conn,
    scope: scope
  } do
    event = event_fixture(scope)

    ballot =
      ballot_fixture(scope, event, %{
        title: "Sabor vencedor",
        options: [
          %{label: "Calabresa", position: 0},
          %{label: "Marguerita", position: 1}
        ]
      })

    participant = event_participant_fixture(scope, event)
    [option | _other_options] = ballot.options

    assert {:ok, %Vote{}} =
             Events.create_vote(scope, event, participant, ballot, %{
               ballot_option_id: option.id,
               intensity: true
             })

    {:ok, view, _html} = live(conn, ~p"/events/#{event}/results")

    assert has_element?(view, "#event-results")
    assert has_element?(view, "#event-results-stats")
    assert has_element?(view, "#ballot-results-list")
    assert has_element?(view, "#ballot-result-#{ballot.id}")
    assert has_element?(view, "#ballot-result-winner-#{ballot.id}", "Calabresa")
    assert has_element?(view, "#ballot-result-option-#{ballot.id}-option-#{option.id}")
    refute has_element?(view, "#event-results-summary")

    view
    |> element("#event-results-summary-generate-button")
    |> render_click()

    assert has_element?(view, "#event-results-summary")
  end

  test "user sees rejected votes in the results report", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
    participant = event_participant_fixture(scope, event, %{display_name: "Ana"})

    assert {:ok, vote} = Events.create_vote(scope, event, participant, ballot, %{value: "yes"})
    assert {:ok, %Vote{}} = Events.reject_vote(scope, vote, %{rejection_reason: "Duplicado"})

    {:ok, view, _html} = live(conn, ~p"/events/#{event}/results")

    assert has_element?(view, "#ballot-result-empty-#{ballot.id}")
    assert has_element?(view, "#ballot-result-rejected-votes-#{ballot.id}")
    assert has_element?(view, "#ballot-result-rejected-vote-#{vote.id}", "Duplicado")
  end

  test "user cannot access results for another user's event", %{conn: conn} do
    event = event_fixture()

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/events/#{event}/results")

    assert path == ~p"/events"
    assert %{"error" => "Evento nao encontrado ou sem acesso."} = flash
  end
end
