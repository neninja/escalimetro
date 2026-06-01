defmodule EscalimetroWeb.EventLiveTest do
  use EscalimetroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Escalimetro.EventsFixtures

  alias Escalimetro.Repo
  alias Escalimetro.Events.Event
  alias Escalimetro.Events.Ballot

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
    assert has_element?(view, "#event-close-button")
    assert has_element?(view, "#event-results-link")

    view
    |> element("#event-close-button")
    |> render_click()

    assert Repo.get!(Event, event.id).status == "closed"
    assert Repo.get!(Ballot, ballot.id).status == "closed"
    refute has_element?(view, "#event-close-button")
  end

  test "user closes an individual ballot without closing others", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event)
    other_ballot = ballot_fixture(scope, event)

    {:ok, view, _html} = live(conn, ~p"/events/#{event}")

    assert has_element?(view, "#ballots-list")
    assert has_element?(view, "#ballot-close-button-#{ballot.id}")

    view
    |> element("#ballot-close-button-#{ballot.id}")
    |> render_click()

    assert Repo.get!(Ballot, ballot.id).status == "closed"
    assert Repo.get!(Ballot, other_ballot.id).status == "open"
    assert has_element?(view, "#ballot-reopen-button-#{ballot.id}")
  end

  test "closed event cannot be edited", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    {:ok, closed_event} = Escalimetro.Events.close_event(scope, event)

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/events/#{closed_event}/edit")

    assert path == ~p"/events/#{closed_event}"
    assert %{"error" => "Eventos fechados nao podem ser editados."} = flash
  end
end
