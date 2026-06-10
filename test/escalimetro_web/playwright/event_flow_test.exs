defmodule EscalimetroWeb.Playwright.EventFlowTest do
  use PhoenixTest.Playwright.Case, async: false, browser_pool: false

  use EscalimetroWeb, :verified_routes

  import Escalimetro.AccountsFixtures
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events.{Ballot, Event}
  alias Escalimetro.Repo

  test "authenticated user creates edits and completes an event", %{conn: conn} do
    user = user_fixture() |> set_password()
    title = unique_event_title()
    updated_title = unique_event_title()

    session =
      conn
      |> log_in_with_magic_link(user)
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
    |> log_in_with_magic_link(user)
    |> visit(~p"/events/#{other_event}")
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

  defp event_from_current_path(session) do
    [id] =
      session
      |> PhoenixTest.Playwright.current_path()
      |> then(&Regex.run(~r{^/events/(\d+)}, &1, capture: :all_but_first))

    Repo.get!(Event, id)
  end
end
