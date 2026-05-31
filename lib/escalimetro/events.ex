defmodule Escalimetro.Events do
  @moduledoc """
  Event management, ballots, participants and votes.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Escalimetro.Accounts.{Scope, User}
  alias Escalimetro.Events.{Ballot, BallotOption, Event, EventAdmin, EventParticipant, Vote}
  alias Escalimetro.Repo

  ## Events

  def list_events(%Scope{user: %User{id: user_id}}) do
    user_id
    |> manageable_events_query()
    |> order_by([e], asc: e.status, asc_nulls_last: e.scheduled_at, desc: e.inserted_at)
    |> Repo.all()
  end

  def list_events(_scope), do: []

  def get_event!(%Scope{user: %User{id: user_id}}, id) do
    user_id
    |> manageable_events_query()
    |> where([e], e.id == ^id)
    |> preload([:owner_user, event_admins: :user])
    |> Repo.one!()
  end

  def get_event!(_scope, _id), do: raise(Ecto.NoResultsError, queryable: Event)

  def change_event(%Scope{} = scope, %Event{} = event, attrs \\ %{}) do
    scope
    |> put_event_owner(event)
    |> Event.changeset(attrs)
  end

  def create_event(%Scope{user: %User{id: user_id}}, attrs) do
    %Event{owner_user_id: user_id}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  def create_event(_scope, _attrs), do: {:error, :unauthorized}

  def update_event(%Scope{} = scope, %Event{} = event, attrs) do
    with :ok <- authorize_event_management(scope, event),
         :ok <- ensure_event_editable(event) do
      event
      |> Event.changeset(attrs)
      |> Repo.update()
    end
  end

  def complete_event(%Scope{} = scope, %Event{} = event) do
    with :ok <- authorize_event_management(scope, event),
         :ok <- ensure_event_editable(event) do
      now = DateTime.utc_now(:second)

      Multi.new()
      |> Multi.update(:event, Event.complete_changeset(event, now))
      |> Multi.update_all(:ballots, open_ballots_query(event.id),
        set: [status: "closed", closed_at: now, updated_at: now]
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{event: event}} -> {:ok, event}
        {:error, _operation, changeset, _changes} -> {:error, changeset}
      end
    end
  end

  def can_manage_event?(%Scope{user: %User{id: user_id}}, %Event{owner_user_id: user_id}),
    do: true

  def can_manage_event?(%Scope{user: %User{id: user_id}}, %Event{id: event_id})
      when not is_nil(event_id) do
    Repo.exists?(
      from admin in EventAdmin,
        where: admin.event_id == ^event_id and admin.user_id == ^user_id
    )
  end

  def can_manage_event?(_scope, _event), do: false

  def add_event_admin(%Scope{} = scope, %Event{} = event, %User{} = user) do
    with :ok <- authorize_event_management(scope, event) do
      %EventAdmin{event_id: event.id, user_id: user.id}
      |> EventAdmin.changeset(%{})
      |> Repo.insert()
    end
  end

  ## Ballots

  def list_ballots(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      Ballot
      |> where(event_id: ^event.id)
      |> order_by([b], asc: b.position, asc: b.inserted_at)
      |> Repo.all()
    else
      []
    end
  end

  def get_ballot!(%Scope{} = scope, %Event{} = event, id) do
    _event = get_event!(scope, event.id)

    Ballot
    |> where(event_id: ^event.id)
    |> Repo.get!(id)
  end

  def change_ballot(%Scope{} = _scope, %Ballot{} = ballot, attrs \\ %{}) do
    Ballot.changeset(ballot, attrs)
  end

  def create_ballot(%Scope{} = scope, %Event{} = event, attrs) do
    with :ok <- authorize_event_management(scope, event),
         :ok <- ensure_event_editable(event) do
      %Ballot{event_id: event.id}
      |> Ballot.changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_ballot(%Scope{} = scope, %Ballot{} = ballot, attrs) do
    event = get_event!(scope, ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      ballot
      |> Ballot.changeset(attrs)
      |> Repo.update()
    end
  end

  ## Ballot options

  def list_ballot_options(%Scope{} = scope, %Ballot{} = ballot) do
    _event = get_event!(scope, ballot.event_id)

    BallotOption
    |> where(ballot_id: ^ballot.id)
    |> order_by([o], asc: o.position, asc: o.inserted_at)
    |> Repo.all()
  end

  def change_ballot_option(%Scope{} = _scope, %BallotOption{} = ballot_option, attrs \\ %{}) do
    BallotOption.changeset(ballot_option, attrs)
  end

  def create_ballot_option(%Scope{} = scope, %Ballot{} = ballot, attrs) do
    event = get_event!(scope, ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      %BallotOption{ballot_id: ballot.id}
      |> BallotOption.changeset(attrs)
      |> Repo.insert()
    end
  end

  ## Participants

  def list_event_participants(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      EventParticipant
      |> where(event_id: ^event.id)
      |> order_by([p], asc: p.display_name, asc: p.inserted_at)
      |> Repo.all()
    else
      []
    end
  end

  def change_event_participant(
        %Scope{} = _scope,
        %EventParticipant{} = event_participant,
        attrs \\ %{}
      ) do
    EventParticipant.changeset(event_participant, attrs)
  end

  def create_event_participant(%Scope{} = scope, %Event{} = event, attrs) do
    with :ok <- authorize_event_management(scope, event) do
      %EventParticipant{event_id: event.id}
      |> EventParticipant.changeset(attrs)
      |> Repo.insert()
    end
  end

  def create_user_participant(%Scope{} = scope, %Event{} = event, %User{} = user, attrs \\ %{}) do
    with :ok <- authorize_event_management(scope, event) do
      attrs = put_param(attrs, :kind, "kind", "user")

      %EventParticipant{event_id: event.id, user_id: user.id}
      |> EventParticipant.changeset(attrs)
      |> Repo.insert()
    end
  end

  ## Votes

  def list_votes(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      Vote
      |> where(event_id: ^event.id)
      |> preload([:participant, :ballot, :ballot_option])
      |> Repo.all()
    else
      []
    end
  end

  def change_vote(%Scope{} = _scope, %Vote{} = vote, attrs \\ %{}) do
    Vote.changeset(vote, attrs)
  end

  def create_vote(
        %Scope{} = _scope,
        %Event{} = event,
        %EventParticipant{} = participant,
        %Ballot{} = ballot,
        attrs
      ) do
    with :ok <- ensure_vote_context(event, participant, ballot),
         :ok <- ensure_event_accepts_votes(event),
         :ok <- ensure_ballot_open(ballot) do
      %Vote{event_id: event.id, ballot_id: ballot.id, participant_id: participant.id}
      |> Vote.changeset(attrs)
      |> Repo.insert()
    end
  end

  def reject_vote(%Scope{} = scope, %Vote{} = vote, attrs) do
    event = get_event!(scope, vote.event_id)

    with :ok <- authorize_event_management(scope, event) do
      vote
      |> Vote.reject_changeset(scope.user.id, attrs)
      |> Repo.update()
    end
  end

  defp manageable_events_query(user_id) do
    from event in Event,
      left_join: admin in EventAdmin,
      on: admin.event_id == event.id and admin.user_id == ^user_id,
      where: event.owner_user_id == ^user_id or not is_nil(admin.id),
      distinct: event.id
  end

  defp put_event_owner(%Scope{user: %User{id: user_id}}, %Event{owner_user_id: nil} = event) do
    %Event{event | owner_user_id: user_id}
  end

  defp put_event_owner(_scope, event), do: event

  defp authorize_event_management(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp ensure_event_editable(%Event{status: "completed"}), do: {:error, :completed_event}
  defp ensure_event_editable(%Event{}), do: :ok

  defp ensure_event_accepts_votes(%Event{status: "completed"}), do: {:error, :completed_event}
  defp ensure_event_accepts_votes(%Event{}), do: :ok

  defp ensure_ballot_open(%Ballot{status: "open"}), do: :ok
  defp ensure_ballot_open(%Ballot{}), do: {:error, :closed_ballot}

  defp ensure_vote_context(%Event{id: event_id}, %EventParticipant{event_id: event_id}, %Ballot{
         event_id: event_id
       }) do
    :ok
  end

  defp ensure_vote_context(_event, _participant, _ballot), do: {:error, :invalid_vote_context}

  defp open_ballots_query(event_id) do
    from ballot in Ballot,
      where: ballot.event_id == ^event_id and ballot.status == "open"
  end

  defp put_param(%{} = params, atom_key, string_key, value) do
    if Enum.any?(params, fn {key, _value} -> is_binary(key) end) do
      Map.put(params, string_key, value)
    else
      Map.put(params, atom_key, value)
    end
  end
end
