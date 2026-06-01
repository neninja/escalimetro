defmodule EscalimetroWeb.BallotLive.FormTest do
  use EscalimetroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events.{Ballot, BallotOption}
  alias Escalimetro.Repo

  setup :register_and_log_in_user

  test "user creates a multiple choice ballot with options", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/events/#{event}/ballots/new")

    assert has_element?(view, "#ballot-form")
    assert has_element?(view, "#ballot-kind-input")
    assert has_element?(view, "#ballot-option-input-0")
    assert has_element?(view, "#ballot-option-input-1")

    title = unique_ballot_title()

    redirect =
      view
      |> form("#ballot-form",
        ballot: %{
          title: title,
          kind: "multiple_choice",
          allow_suggestion: "true",
          position: "0",
          options: %{
            "0" => %{label: "Manha", position: "0"},
            "1" => %{label: "Noite", position: "1"}
          }
        }
      )
      |> render_submit()

    ballot = Repo.get_by!(Ballot, title: title)
    options = Repo.all(from option in BallotOption, where: option.ballot_id == ^ballot.id)

    assert ballot.allow_suggestion
    assert Enum.map(options, & &1.label) |> Enum.sort() == ["Manha", "Noite"]
    assert {:ok, _show, _html} = follow_redirect(redirect, conn, ~p"/events/#{event}")
  end

  test "multiple choice ballot validates minimum options", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/events/#{event}/ballots/new")

    html =
      view
      |> form("#ballot-form",
        ballot: %{
          title: "Pauta incompleta",
          kind: "multiple_choice",
          options: %{"0" => %{label: "Unica"}}
        }
      )
      |> render_submit()

    assert html =~ "must have at least two options"
  end

  test "user edits ballot options", %{conn: conn, scope: scope} do
    event = event_fixture(scope)
    ballot = ballot_fixture(scope, event)
    [first_option, second_option] = ballot.options

    {:ok, view, _html} = live(conn, ~p"/events/#{event}/ballots/#{ballot}/edit")

    redirect =
      view
      |> form("#ballot-form",
        ballot: %{
          title: "Pauta editada",
          kind: "multiple_choice",
          options: %{
            "0" => %{id: first_option.id, label: "Tarde"},
            "1" => %{id: second_option.id, label: "Noite"}
          }
        }
      )
      |> render_submit()

    assert Repo.get!(Ballot, ballot.id).title == "Pauta editada"
    assert {:ok, _show, _html} = follow_redirect(redirect, conn, ~p"/events/#{event}")
  end

  test "user cannot access ballot form for another user's event", %{conn: conn} do
    event = event_fixture()

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/events/#{event}/ballots/new")

    assert path == ~p"/events"
    assert %{"error" => "Evento nao encontrado ou sem acesso."} = flash
  end
end
