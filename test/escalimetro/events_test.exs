defmodule Escalimetro.EventsTest do
  use Escalimetro.DataCase, async: true

  alias Escalimetro.Events
  alias Escalimetro.Events.{Ballot, Event, EventAdmin, Vote}

  import Escalimetro.AccountsFixtures
  import Escalimetro.EventsFixtures

  describe "events" do
    test "create_event/2 validates required title and enum status" do
      scope = user_scope_fixture()

      assert {:error, changeset} = Events.create_event(scope, %{title: nil})
      assert "can't be blank" in errors_on(changeset).title

      assert {:error, changeset} =
               Events.create_event(scope, %{title: "Assembleia", status: "bad"})

      assert "is invalid" in errors_on(changeset).status
    end

    test "create_event/2 sets owner_user_id from current_scope and ignores attrs owner" do
      scope = user_scope_fixture()
      other_user = user_fixture()

      assert {:ok, event} =
               Events.create_event(scope, %{
                 title: "Assembleia anual",
                 owner_user_id: other_user.id
               })

      assert event.owner_user_id == scope.user.id
    end

    test "list_events/1 returns owned and administered events only" do
      owner_scope = user_scope_fixture()
      admin = user_fixture()
      admin_scope = user_scope_fixture(admin)
      other_scope = user_scope_fixture()

      owned_event = event_fixture(owner_scope)
      administered_event = event_fixture(other_scope)
      hidden_event = event_fixture(user_scope_fixture())

      assert {:ok, %EventAdmin{}} = Events.add_event_admin(other_scope, administered_event, admin)

      owner_ids = owner_scope |> Events.list_events() |> Enum.map(& &1.id)
      admin_ids = admin_scope |> Events.list_events() |> Enum.map(& &1.id)

      assert owned_event.id in owner_ids
      refute hidden_event.id in owner_ids
      assert administered_event.id in admin_ids
      refute hidden_event.id in admin_ids
    end

    test "get_event!/2 denies events from another user" do
      event = event_fixture(user_scope_fixture())
      other_scope = user_scope_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Events.get_event!(other_scope, event.id)
      end
    end

    test "update_event/3 blocks completed events" do
      scope = user_scope_fixture()
      event = event_fixture(scope)

      assert {:ok, completed_event} = Events.complete_event(scope, event)

      assert {:error, :completed_event} =
               Events.update_event(scope, completed_event, %{title: "Novo"})
    end

    test "complete_event/2 closes open ballots" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event)

      assert {:ok, %Event{status: "completed", completed_at: completed_at}} =
               Events.complete_event(scope, event)

      assert completed_at
      assert %Ballot{status: "closed", closed_at: closed_at} = Repo.get!(Ballot, ballot.id)
      assert closed_at
    end
  end

  describe "event admins" do
    test "event admin is unique by event and user" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      admin = user_fixture()

      assert {:ok, %EventAdmin{}} = Events.add_event_admin(scope, event, admin)
      assert {:error, changeset} = Events.add_event_admin(scope, event, admin)
      assert "has already been taken" in errors_on(changeset).event_id
    end
  end

  describe "ballots" do
    test "create_ballot/3 validates required fields and enums" do
      scope = user_scope_fixture()
      event = event_fixture(scope)

      assert {:error, changeset} = Events.create_ballot(scope, event, %{kind: "bad"})

      assert "can't be blank" in errors_on(changeset).title
      assert "is invalid" in errors_on(changeset).kind
    end
  end

  describe "participants" do
    test "guest participant requires display name" do
      scope = user_scope_fixture()
      event = event_fixture(scope)

      assert {:error, changeset} =
               Events.create_event_participant(scope, event, %{kind: "guest", status: "active"})

      assert "can't be blank" in errors_on(changeset).display_name
    end
  end

  describe "votes" do
    test "create_vote/5 validates value enums and option-or-value requirement" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)

      assert {:error, changeset} = Events.create_vote(scope, event, participant, ballot, %{})
      assert "or value must be present" in errors_on(changeset).ballot_option_id

      assert {:error, changeset} =
               Events.create_vote(scope, event, participant, ballot, %{value: "sometimes"})

      assert "is invalid" in errors_on(changeset).value
    end

    test "active value vote is unique by event ballot and participant" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)

      assert {:ok, %Vote{}} =
               Events.create_vote(scope, event, participant, ballot, %{value: "yes"})

      assert {:error, changeset} =
               Events.create_vote(scope, event, participant, ballot, %{value: "no"})

      assert "has already been taken" in errors_on(changeset).participant_id
    end

    test "completed events do not accept votes" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)

      assert {:ok, completed_event} = Events.complete_event(scope, event)
      closed_ballot = Repo.get!(Ballot, ballot.id)

      assert {:error, :completed_event} =
               Events.create_vote(scope, completed_event, participant, closed_ballot, %{
                 value: "yes"
               })
    end
  end
end
