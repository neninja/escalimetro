defmodule EscalimetroWeb.Playwright.EventFlowTest do
  use PhoenixTest.Playwright.Case, async: false, browser_pool: false

  use EscalimetroWeb, :verified_routes

  import Escalimetro.AccountsFixtures
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events.{Ballot, BallotOption, Event, EventParticipant, Vote}
  alias Escalimetro.Repo

  test "authenticated user creates edits and completes an event", %{conn: conn} do
    user = user_fixture() |> set_password()
    title = unique_event_title()
    updated_title = unique_event_title()

    session =
      conn
      |> log_in_with_password(user.email)
      |> visit(~p"/events")
      |> click_link("Novo evento")
      |> assert_path(~p"/events/new")
      |> within("#event-form", fn session ->
        session
        |> fill_in("Titulo", with: title)
        |> fill_in("Descricao", with: "Discussao de prioridades")
        |> fill_in("Local", with: "Auditorio")
        |> click_button("Salvar evento")
      end)
      |> assert_has("#flash-info", text: "Evento criado com sucesso.")

    event = event_from_current_path(session)
    assert event.title == title

    session =
      session
      |> assert_path(~p"/events/#{event}", timeout: 5_000)
      |> assert_has("#event-complete-button")
      |> click_link("Editar")
      |> assert_path(~p"/events/#{event}/edit")
      |> within("#event-form", fn session ->
        session
        |> fill_in("Titulo", with: updated_title)
        |> click_button("Salvar evento")
      end)
      |> assert_has("#flash-info", text: "Evento atualizado com sucesso.")

    event = event_from_current_path(session)
    assert event.title == updated_title
    ballot = ballot_fixture(user_scope_fixture(user), event)

    session
    |> assert_path(~p"/events/#{event}", timeout: 5_000)
    |> click_button("Concluir")
    |> assert_has("#flash-info", text: "Evento concluido com sucesso.")

    assert Repo.get!(Event, event.id).status == "completed"
    assert Repo.get!(Ballot, ballot.id).status == "closed"
  end

  test "authenticated user is redirected away from another user's event", %{conn: conn} do
    user = user_fixture() |> set_password()
    other_event = event_fixture(user_scope_fixture())

    conn
    |> log_in_with_password(user.email)
    |> visit(~p"/events/#{other_event}")
    |> assert_path(~p"/events")
    |> assert_has("#flash-error", text: "Evento nao encontrado ou sem acesso.")
  end

  test "critical voting journey covers authenticated guest and admin vote review", %{conn: conn} do
    owner = user_fixture() |> set_password()
    logged_voter = user_fixture() |> set_password()
    title = unique_event_title()
    ballot_title = unique_ballot_title()
    option_label = unique_option_label()
    guest_name = "Convidado #{System.unique_integer([:positive])}"

    owner_session =
      conn
      |> log_in_with_password(owner.email)
      |> visit(~p"/events")
      |> click_link("Novo evento")
      |> within("#event-form", fn session ->
        session
        |> fill_in("Titulo", with: title)
        |> fill_in("Descricao", with: "Decisao acompanhada pelo CUJ")
        |> fill_in("Local", with: "Sala CUJ")
        |> click_button("Salvar evento")
      end)
      |> assert_has("#flash-info", text: "Evento criado com sucesso.")

    event = event_from_current_path(owner_session)

    owner_session =
      owner_session
      |> within("#ballot-form", fn session ->
        session
        |> fill_in("Titulo", with: ballot_title)
        |> fill_in("Descricao", with: "Escolha uma opcao")
        |> click_button("Criar pauta")
      end)
      |> assert_has("#flash-info", text: "Pauta criada.")

    ballot = Repo.get_by!(Ballot, event_id: event.id, title: ballot_title)

    owner_session
    |> within("#ballot-option-form-#{ballot.id}", fn session ->
      session
      |> fill_in("Nova opcao", with: option_label)
      |> click_button("Adicionar")
    end)
    |> assert_has("#ballot-#{ballot.id}", text: option_label)

    option = Repo.get_by!(BallotOption, ballot_id: ballot.id, label: option_label)

    voter_session =
      owner_session
      |> clear_cookies()
      |> log_in_with_password(logged_voter.email)
      |> visit(~p"/events/#{event.public_invite_id}/vote")
      |> assert_has("#voting-area")
      |> refute_has("#participant-form")
      |> click("#vote-option-checkbox-#{option.id}")

    logged_participant =
      Repo.get_by!(EventParticipant, event_id: event.id, user_id: logged_voter.id, kind: "user")

    logged_vote =
      Repo.get_by!(Vote,
        event_id: event.id,
        ballot_id: ballot.id,
        participant_id: logged_participant.id,
        ballot_option_id: option.id
      )

    assert logged_vote

    anonymous_session =
      voter_session
      |> clear_cookies()
      |> visit(~p"/events/#{event.public_invite_id}/vote")
      |> assert_has("#participant-form")
      |> refute_has("#voting-area")
      |> within("#participant-form", fn session ->
        session
        |> fill_in("Nome ou apelido", with: guest_name)
        |> click_button("Entrar na votacao")
      end)
      |> assert_has("#voting-area")
      |> click("#vote-option-checkbox-#{option.id}")

    guest_participant =
      Repo.get_by!(EventParticipant, event_id: event.id, display_name: guest_name, kind: "guest")

    guest_vote =
      Repo.get_by!(Vote,
        event_id: event.id,
        ballot_id: ballot.id,
        participant_id: guest_participant.id,
        ballot_option_id: option.id
      )

    assert guest_vote

    anonymous_session
    |> clear_cookies()
    |> log_in_with_password(owner.email)
    |> visit(~p"/events/#{event}")
    |> assert_has("#participant-review-#{logged_participant.id}", text: logged_voter.email)
    |> assert_has("#participant-review-#{guest_participant.id}", text: guest_name)
    |> click("#participant-vote-checkbox-#{logged_vote.id}")
    |> assert_has("#participant-review-#{logged_participant.id}", text: "Sem votos ativos.")
    |> click_button("Ignorar votos")
    |> assert_has("#participant-review-#{guest_participant.id}", text: "Sem votos ativos.")

    refute Repo.get(Vote, logged_vote.id)
    refute Repo.get(Vote, guest_vote.id)
  end

  defp log_in_with_password(conn, email, password \\ valid_user_password()) do
    conn
    |> visit(~p"/users/log-in")
    |> assert_has("#login_form_password")
    |> within("#login_form_password", fn session ->
      session
      |> fill_in("Email", with: email)
      |> fill_in("Password", with: password)
    end)
    |> evaluate(
      "HTMLFormElement.prototype.submit.call(document.querySelector('#login_form_password'))"
    )
    |> assert_path(~p"/", timeout: 5_000)
  end

  defp event_from_current_path(session) do
    [id] =
      session
      |> PhoenixTest.Playwright.current_path()
      |> then(&Regex.run(~r{^/events/(\d+)}, &1, capture: :all_but_first))

    Repo.get!(Event, id)
  end
end
