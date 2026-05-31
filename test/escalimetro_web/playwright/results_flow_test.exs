defmodule EscalimetroWeb.Playwright.ResultsFlowTest do
  use PhoenixTest.Playwright.Case, async: false, browser_pool: false

  use EscalimetroWeb, :verified_routes

  import Escalimetro.AccountsFixtures
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events
  alias Escalimetro.Events.Vote

  test "admin reviews results and generates consolidated summary", %{conn: conn} do
    user = user_fixture() |> set_password()
    scope = user_scope_fixture(user)
    event = event_fixture(scope, %{title: "Noite de pizza", location: "Salao"})

    ballot =
      ballot_fixture(scope, event, %{
        title: "Sabor da pizza",
        options: [
          %{label: "Calabresa", position: 0},
          %{label: "Marguerita", position: 1}
        ]
      })

    [calabresa, marguerita] = ballot.options

    calabresa_voters =
      for _index <- 1..2 do
        event_participant_fixture(scope, event)
      end

    marguerita_voters =
      for _index <- 1..2 do
        event_participant_fixture(scope, event)
      end

    for participant <- calabresa_voters do
      assert {:ok, %Vote{}} =
               Events.create_vote(scope, event, participant, ballot, %{
                 ballot_option_id: calabresa.id
               })
    end

    [intense_voter, regular_voter] = marguerita_voters

    assert {:ok, %Vote{}} =
             Events.create_vote(scope, event, intense_voter, ballot, %{
               ballot_option_id: marguerita.id,
               intensity: true
             })

    assert {:ok, %Vote{}} =
             Events.create_vote(scope, event, regular_voter, ballot, %{
               ballot_option_id: marguerita.id
             })

    rejected_voter = event_participant_fixture(scope, event, %{display_name: "Voto duplicado"})

    assert {:ok, rejected_vote} =
             Events.create_vote(scope, event, rejected_voter, ballot, %{
               ballot_option_id: calabresa.id
             })

    assert {:ok, %Vote{}} =
             Events.reject_vote(scope, rejected_vote, %{rejection_reason: "Duplicado"})

    conn
    |> log_in_with_magic_link(user)
    |> visit(~p"/events/#{event}")
    |> assert_has("#event-results-link")
    |> click_link("Resultados")
    |> assert_path(~p"/events/#{event}/results")
    |> assert_has("#event-results")
    |> assert_has("#event-results-active-votes-count", text: "4")
    |> assert_has("#event-results-rejected-votes-count", text: "1")
    |> assert_has("#ballot-result-winner-#{ballot.id}", text: "Marguerita")
    |> assert_has("#ballot-result-rejected-vote-#{rejected_vote.id}", text: "Duplicado")
    |> click_button("Gerar resumo")
    |> assert_has("#event-results-summary-panel")
    |> assert_has("#event-results-summary", text: "Sabor da pizza: Marguerita")
  end

  test "authenticated user is redirected away from another user's results", %{conn: conn} do
    user = user_fixture() |> set_password()
    other_event = event_fixture(user_scope_fixture())

    conn
    |> log_in_with_magic_link(user)
    |> visit(~p"/events/#{other_event}/results")
    |> assert_path(~p"/events")
    |> assert_has("#flash-error", text: "Evento nao encontrado ou sem acesso.")
  end

  defp log_in_with_magic_link(session, user) do
    {token, _hashed_token} = generate_user_magic_link_token(user)

    session
    |> visit(~p"/users/log-in/#{token}")
    |> assert_has("#login_form")
    |> click_button("Log me in only this time")
    |> assert_path(~p"/", timeout: 5_000)
  end
end
