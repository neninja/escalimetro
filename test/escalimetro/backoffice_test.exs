defmodule Escalimetro.BackofficeTest do
  use Escalimetro.DataCase, async: true

  import Escalimetro.AccountsFixtures
  import Escalimetro.EventsFixtures

  alias Escalimetro.Backoffice
  alias Escalimetro.Events

  describe "dashboard_data/1" do
    test "returns system metrics for system admins" do
      admin = system_admin_fixture()
      scope = user_scope_fixture(admin)
      _user = user_fixture()

      open_event = event_fixture(scope, %{status: "open"})
      event_to_close = event_fixture(scope)
      ballot = ballot_fixture(scope, open_event)
      participant = event_participant_fixture(scope, open_event)
      [option | _options] = ballot.options

      assert {:ok, _vote} =
               Events.create_vote(scope, open_event, participant, ballot, %{
                 ballot_option_id: option.id
               })

      assert {:ok, _closed_event} = Events.close_event(scope, event_to_close)

      assert {:ok, %{stats: stats, users: users}} = Backoffice.dashboard_data(scope)

      assert stats.total_users_count == 2
      assert stats.active_users_count == 2
      assert stats.open_events_count == 1
      assert stats.closed_events_count == 1
      assert stats.open_ballots_count == 1
      assert stats.active_votes_count == 1
      assert Enum.map(users, & &1.id) |> Enum.member?(admin.id)
    end

    test "blocks regular users" do
      scope = user_scope_fixture()

      assert {:error, :unauthorized} = Backoffice.dashboard_data(scope)
    end
  end

  describe "get_user_for_impersonation/2" do
    test "allows system admins to fetch another user" do
      admin = system_admin_fixture()
      target = user_fixture()

      assert {:ok, user} =
               Backoffice.get_user_for_impersonation(user_scope_fixture(admin), target.id)

      assert user.id == target.id
    end

    test "blocks self impersonation and regular users" do
      admin = system_admin_fixture()
      target = user_fixture()

      assert {:error, :self_impersonation} =
               Backoffice.get_user_for_impersonation(user_scope_fixture(admin), admin.id)

      assert {:error, :unauthorized} =
               Backoffice.get_user_for_impersonation(user_scope_fixture(target), admin.id)
    end
  end
end
