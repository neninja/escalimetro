defmodule EscalimetroWeb.Playwright.EventManagementFlowTest do
  use PhoenixTest.Playwright.Case, async: false, browser_pool: false

  use EscalimetroWeb, :verified_routes

  import Escalimetro.AccountsFixtures
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events.{Ballot, EventParticipant, Vote}
  alias Escalimetro.Repo

  test "admin creates and closes a ballot", %{conn: conn} do
    user = user_fixture() |> set_password()
    scope = user_scope_fixture(user)
    event = event_fixture(scope)
    title = unique_ballot_title()

    session =
      conn
      |> log_in_with_magic_link(user)
      |> visit(~p"/events/#{event}")
      |> click_link("Nova pauta")
      |> assert_path(~p"/events/#{event}/ballots/new")
      |> within("#ballot-form", fn session ->
        session
        |> fill_in("Titulo da pauta", with: title)
        |> fill_in("Opcao 1", with: "Manha")
        |> fill_in("Opcao 2", with: "Noite")
        |> click_button("Salvar pauta")
      end)
      |> assert_has("#flash-info", text: "Pauta criada com sucesso.")
      |> assert_path(~p"/events/#{event}", timeout: 5_000)

    ballot = Repo.get_by!(Ballot, title: title)

    session
    |> click_button("#ballot-close-button-#{ballot.id}", "Fechar")
    |> assert_has("#flash-info", text: "Pauta fechada com sucesso.")

    assert Repo.get_by!(Ballot, title: title).status == "closed"
  end

  test "admin invalidates participant and sees votes as immediately computed", %{conn: conn} do
    user = user_fixture() |> set_password()
    scope = user_scope_fixture(user)
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})

    invalidated_participant = event_participant_fixture(scope, event)

    invalidated_vote =
      vote_fixture(scope, event, invalidated_participant, ballot, %{value: "yes"})

    active_participant = event_participant_fixture(scope, event)
    active_vote = vote_fixture(scope, event, active_participant, ballot, %{value: "no"})

    session =
      conn
      |> log_in_with_magic_link(user)
      |> visit(~p"/events/#{event}/participants")
      |> assert_has("#participants-list")
      |> click_button("#participant-invalidate-button-#{invalidated_participant.id}", "Invalidar")
      |> assert_has("#flash-info", text: "Participante invalidado com sucesso.")

    assert Repo.get!(EventParticipant, invalidated_participant.id).status == "invalidated"
    assert Repo.get!(Vote, invalidated_vote.id).rejected_at

    session
    |> visit(~p"/events/#{event}/moderation")
    |> assert_has("#moderation-votes-list")
    |> assert_has("#moderation-vote-immediate-note-#{active_vote.id}")

    assert is_nil(Repo.get!(Vote, active_vote.id).rejected_at)
  end

  defp log_in_with_magic_link(session, user) do
    {token, _hashed_token} = generate_user_magic_link_token(user)

    session
    |> visit(~p"/users/log-in/#{token}")
    |> assert_has("#login_form")
    |> click_button("Entrar apenas desta vez")
    |> assert_path(~p"/events", timeout: 5_000)
  end
end
