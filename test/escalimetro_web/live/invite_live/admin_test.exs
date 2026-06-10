defmodule EscalimetroWeb.InviteLive.AdminTest do
  use EscalimetroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Escalimetro.EventsFixtures

  alias Escalimetro.Events

  setup :register_and_log_in_user

  test "user generates rotates and invalidates an event invite", %{conn: conn, scope: scope} do
    event = event_fixture(scope)

    {:ok, view, _html} = live(conn, ~p"/events/#{event}/invite")

    assert has_element?(view, "#event-invite-url")
    assert has_element?(view, "#event-invite-copy-button")
    assert has_element?(view, "#event-invite-rotate-button")
    assert has_element?(view, "#event-invite-invalidate-button")
    assert has_element?(view, "#event-invite-qrcode")

    first_url = invite_url(view)
    first_token = invite_token(first_url)
    assert first_url =~ ~p"/join/#{first_token}"
    assert Events.get_active_invite_by_token(first_token)
    assert render(element(view, "#event-invite-qrcode")) =~ first_url

    view
    |> element("#event-invite-rotate-button")
    |> render_click()

    second_url = invite_url(view)
    second_token = invite_token(second_url)
    assert first_token != second_token
    assert Events.get_active_invite_by_token(first_token) == nil
    assert Events.get_active_invite_by_token(second_token)

    view
    |> element("#event-invite-invalidate-button")
    |> render_click()

    assert Events.get_active_invite_by_token(second_token) == nil
    assert has_element?(view, "#event-invite-invalidate-button[disabled]")
  end

  test "user cannot access invite admin for another user's event", %{conn: conn} do
    event = event_fixture()

    assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
             live(conn, ~p"/events/#{event}/invite")

    assert path == ~p"/events"
    assert %{"error" => "Evento nao encontrado ou sem acesso."} = flash
  end

  defp invite_url(view) do
    html =
      view
      |> element("#event-invite-url")
      |> render()

    [_, url] = Regex.run(~r/value="([^"]+)"/, html)
    url
  end

  defp invite_token(url) do
    url
    |> URI.parse()
    |> Map.fetch!(:path)
    |> String.split("/join/")
    |> List.last()
  end
end
