defmodule EscalimetroWeb.ParticipantLive.EventTest do
  use EscalimetroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events.{BallotOption, Vote}
  alias Escalimetro.Repo

  test "guest who enters through invite has vote counted immediately", %{conn: conn} do
    scope = Escalimetro.AccountsFixtures.user_scope_fixture()
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event)
    [option | _] = ballot.options

    assert {:ok, invite} = Escalimetro.Events.rotate_event_invite(scope, event)

    assert {:ok, participant} =
             Escalimetro.Events.enter_event_invite(%Escalimetro.Accounts.Scope{}, invite, %{
               "display_name" => "Visitante"
             })

    {:ok, view, _html} = live(conn, ~p"/events/public/#{participant.participant_token}")

    assert has_element?(view, "#participant-ballot-results-#{ballot.id}", "0 voto(s)")

    view
    |> form("#vote-form-#{ballot.id}", vote: %{ballot_option_id: option.id})
    |> render_submit()

    assert %Vote{ballot_option_id: option_id, rejected_at: nil} =
             Repo.get_by!(Vote, participant_id: participant.id, ballot_id: ballot.id)

    assert option_id == option.id
    assert has_element?(view, "#participant-ballot-results-#{ballot.id}", "1 voto(s)")

    assert has_element?(
             view,
             "#participant-result-option-#{ballot.id}-option-#{option.id}",
             "Visitante"
           )
  end

  test "participant votes in a multiple choice ballot with justification", %{conn: conn} do
    scope = Escalimetro.AccountsFixtures.user_scope_fixture()
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event)
    participant = event_participant_fixture(scope, event)
    [option | _] = ballot.options

    {:ok, view, _html} = live(conn, ~p"/events/public/#{participant.participant_token}")

    assert has_element?(view, "#participant-event")
    assert has_element?(view, "#ballots-voting-list")
    assert has_element?(view, "#ballot-card-#{ballot.id}")
    assert has_element?(view, "#vote-option-button-#{option.id}")
    assert has_element?(view, "#vote-intensity-checkbox-#{ballot.id}")
    assert has_element?(view, "#vote-justification-input-#{ballot.id}")
    assert has_element?(view, "#vote-submit-button-#{ballot.id}")

    view
    |> form("#vote-form-#{ballot.id}",
      vote: %{
        ballot_option_id: option.id,
        intensity: "true",
        justification: "Minha justificativa"
      }
    )
    |> render_submit()

    assert %Vote{
             ballot_option_id: option_id,
             intensity: true,
             justification: "Minha justificativa"
           } =
             Repo.get_by!(Vote, participant_id: participant.id, ballot_id: ballot.id)

    assert option_id == option.id
    assert has_element?(view, "#vote-option-button-#{option.id}[aria-pressed=true]")
    assert has_element?(view, "#vote-option-selected-label-#{option.id}")
  end

  test "participant votes in a yes no maybe ballot", %{conn: conn} do
    scope = Escalimetro.AccountsFixtures.user_scope_fixture()
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
    participant = event_participant_fixture(scope, event)

    {:ok, view, _html} = live(conn, ~p"/events/public/#{participant.participant_token}")

    assert has_element?(view, "#vote-option-button-#{ballot.id}-yes")
    refute has_element?(view, "#vote-intensity-checkbox-#{ballot.id}")

    view
    |> form("#vote-form-#{ballot.id}", vote: %{value: "yes"})
    |> render_submit()

    assert %Vote{value: "yes", intensity: false} =
             Repo.get_by!(Vote, participant_id: participant.id, ballot_id: ballot.id)

    assert has_element?(view, "#vote-option-button-#{ballot.id}-yes[aria-pressed=true]")
    assert has_element?(view, "#vote-option-selected-label-#{ballot.id}-yes")
  end

  test "participant sees live counts details and can remove a vote", %{conn: conn} do
    scope = Escalimetro.AccountsFixtures.user_scope_fixture()
    event = event_fixture(scope)

    ballot =
      ballot_fixture(scope, event, %{
        selection_mode: "multi_choice",
        show_justifications: true
      })

    participant = event_participant_fixture(scope, event, %{display_name: "Ana"})
    [option | _] = ballot.options

    {:ok, view, _html} = live(conn, ~p"/events/public/#{participant.participant_token}")

    view
    |> form("#vote-form-#{ballot.id}",
      vote: %{
        ballot_option_id: option.id,
        intensity: "true",
        justification: "Muito importante"
      }
    )
    |> render_submit()

    assert has_element?(view, "#participant-ballot-results-#{ballot.id}", "1 voto(s)")

    assert has_element?(
             view,
             "#participant-result-option-#{ballot.id}-option-#{option.id}",
             "Ana"
           )

    assert has_element?(view, "[id^=participant-result-vote-]", "Muito importante")

    view
    |> element("#vote-remove-option-button-#{option.id}")
    |> render_click()

    assert has_element?(view, "#participant-ballot-results-#{ballot.id}", "0 voto(s)")

    assert %Vote{rejection_reason: "Voto removido"} =
             Repo.get_by!(Vote, participant_id: participant.id, ballot_id: ballot.id)
  end

  test "intensity changes appear in another connected participant view", %{conn: conn} do
    scope = Escalimetro.AccountsFixtures.user_scope_fixture()
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event)
    participant = event_participant_fixture(scope, event)
    [option | _] = ballot.options

    {:ok, view, _html} = live(conn, ~p"/events/public/#{participant.participant_token}")

    {:ok, other_view, _html} =
      live(build_conn(), ~p"/events/public/#{participant.participant_token}")

    refute has_element?(other_view, "#vote-intensity-checkbox-#{ballot.id}[checked]")

    view
    |> form("#vote-form-#{ballot.id}",
      vote: %{ballot_option_id: option.id, intensity: "true"}
    )
    |> render_submit()

    render(other_view)
    assert has_element?(other_view, "#vote-intensity-checkbox-#{ballot.id}[checked]")

    view
    |> form("#vote-form-#{ballot.id}",
      vote: %{ballot_option_id: option.id, intensity: "false"}
    )
    |> render_submit()

    render(other_view)
    refute has_element?(other_view, "#vote-intensity-checkbox-#{ballot.id}[checked]")
  end

  test "suggestion appears in another connected participant view and can receive votes", %{
    conn: conn
  } do
    scope = Escalimetro.AccountsFixtures.user_scope_fixture()
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event, %{allow_suggestion: true})
    participant = event_participant_fixture(scope, event)
    other_participant = event_participant_fixture(scope, event)

    {:ok, view, _html} = live(conn, ~p"/events/public/#{participant.participant_token}")

    {:ok, other_view, _html} =
      live(build_conn(), ~p"/events/public/#{other_participant.participant_token}")

    assert has_element?(view, "#suggestion-form-#{ballot.id}")
    assert has_element?(view, "#suggestion-label-input-#{ballot.id}")
    assert has_element?(view, "#suggestion-submit-button-#{ballot.id}")
    assert has_element?(view, "#suggested-options-list-#{ballot.id}")

    view
    |> form("#suggestion-form-#{ballot.id}", suggestion: %{label: "Opcao sugerida"})
    |> render_submit()

    option = Repo.get_by!(BallotOption, ballot_id: ballot.id, label: "Opcao sugerida")

    assert render(other_view) =~ "Opcao sugerida"
    assert has_element?(other_view, "#vote-option-button-#{option.id}")

    other_view
    |> form("#vote-form-#{ballot.id}", vote: %{ballot_option_id: option.id})
    |> render_submit()

    assert %Vote{ballot_option_id: option_id} =
             Repo.get_by!(Vote, participant_id: other_participant.id, ballot_id: ballot.id)

    assert option_id == option.id
  end

  test "closed ballot blocks voting in already connected views", %{conn: conn} do
    scope = Escalimetro.AccountsFixtures.user_scope_fixture()
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event)
    participant = event_participant_fixture(scope, event)
    [option | _] = ballot.options

    {:ok, view, _html} = live(conn, ~p"/events/public/#{participant.participant_token}")
    assert has_element?(view, "#vote-option-button-#{option.id}")

    assert {:ok, _ballot} = Escalimetro.Events.close_ballot(scope, ballot)

    assert render(view) =~ "Pauta fechada."
    assert has_element?(view, "#vote-option-button-#{option.id}[disabled]")

    refute Repo.get_by(Vote, participant_id: participant.id, ballot_id: ballot.id)
  end
end
