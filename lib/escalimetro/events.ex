defmodule Escalimetro.Events do
  @moduledoc """
  Event management, ballots, participants and votes.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Escalimetro.Accounts.{Scope, User}
  alias EscalimetroWeb.Endpoint
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

  def get_public_event_by_invite!(public_invite_id) do
    Event
    |> where(public_invite_id: ^public_invite_id)
    |> preload(:owner_user)
    |> Repo.one!()
  end

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
        {:ok, %{event: event}} ->
          broadcast_event(event.id)
          {:ok, event}

        {:error, _operation, changeset, _changes} ->
          {:error, changeset}
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
      |> preload([:options, votes: [:participant, :ballot_option]])
      |> order_by([b], asc: b.position, asc: b.inserted_at)
      |> Repo.all()
    else
      []
    end
  end

  def list_public_ballots(%Event{} = event) do
    Ballot
    |> where(event_id: ^event.id)
    |> preload([:options, votes: [:participant, :ballot_option]])
    |> order_by([b], asc: b.position, asc: b.inserted_at)
    |> Repo.all()
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
      |> broadcast_result(event.id)
    end
  end

  def update_ballot(%Scope{} = scope, %Ballot{} = ballot, attrs) do
    event = get_event!(scope, ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      ballot
      |> Ballot.changeset(attrs)
      |> Repo.update()
      |> broadcast_result(event.id)
    end
  end

  def close_ballot(%Scope{} = scope, %Ballot{} = ballot) do
    event = get_event!(scope, ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      ballot
      |> Ballot.close_changeset(DateTime.utc_now(:second))
      |> Repo.update()
      |> broadcast_result(event.id)
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

  def change_ballot_option(_scope, %BallotOption{} = ballot_option, attrs \\ %{}) do
    BallotOption.changeset(ballot_option, attrs)
  end

  def create_ballot_option(%Scope{} = scope, %Ballot{} = ballot, attrs) do
    event = get_event!(scope, ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      %BallotOption{ballot_id: ballot.id}
      |> BallotOption.changeset(attrs)
      |> Repo.insert()
      |> broadcast_result(event.id)
    end
  end

  def suggest_ballot_option(
        %Event{} = event,
        %EventParticipant{} = participant,
        %Ballot{} = ballot,
        attrs
      ) do
    with :ok <- ensure_vote_context(event, participant, ballot),
         :ok <- ensure_event_accepts_votes(event),
         :ok <- ensure_ballot_open(ballot),
         :ok <- ensure_ballot_accepts_suggestions(ballot) do
      %BallotOption{ballot_id: ballot.id, suggested_by_participant_id: participant.id}
      |> BallotOption.changeset(attrs)
      |> Repo.insert()
      |> broadcast_result(event.id)
    end
  end

  ## Participants

  def list_event_participants(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      EventParticipant
      |> where(event_id: ^event.id)
      |> order_by([p], asc: p.inserted_at, asc: p.id)
      |> Repo.all()
    else
      []
    end
  end

  def list_event_participants_for_review(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      EventParticipant
      |> where(event_id: ^event.id)
      |> order_by([p], asc: p.inserted_at, asc: p.id)
      |> preload(votes: [:ballot, :ballot_option])
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

  def create_guest_participant(%Event{} = event, attrs) do
    %EventParticipant{event_id: event.id, kind: "guest", status: "active"}
    |> EventParticipant.changeset(attrs)
    |> Repo.insert()
    |> broadcast_result(event.id)
  end

  def get_active_public_participant(%Event{} = event, participant_id) do
    EventParticipant
    |> where(event_id: ^event.id, id: ^participant_id, status: "active")
    |> Repo.one()
  end

  def get_or_create_user_participant(%Event{} = event, %User{} = user) do
    case Repo.get_by(EventParticipant, event_id: event.id, user_id: user.id, kind: "user") do
      %EventParticipant{} = participant ->
        {:ok, participant}

      nil ->
        %EventParticipant{event_id: event.id, user_id: user.id, kind: "user", status: "active"}
        |> EventParticipant.changeset(%{})
        |> Repo.insert()
        |> broadcast_result(event.id)
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
      |> broadcast_result(event.id)
    end
  end

  def create_public_vote(
        %Event{} = event,
        %EventParticipant{} = participant,
        %Ballot{} = ballot,
        attrs
      ) do
    with :ok <- ensure_vote_context(event, participant, ballot),
         :ok <- ensure_active_participant(participant),
         :ok <- ensure_event_accepts_votes(event),
         :ok <- ensure_ballot_open(ballot),
         :ok <- ensure_vote_matches_ballot(ballot, attrs) do
      %Vote{event_id: event.id, ballot_id: ballot.id, participant_id: participant.id}
      |> Vote.changeset(attrs)
      |> Repo.insert()
      |> broadcast_result(event.id)
    end
  end

  def toggle_public_option_vote(
        %Event{} = event,
        %EventParticipant{} = participant,
        %Ballot{kind: "multiple_choice"} = ballot,
        %BallotOption{} = option
      ) do
    with :ok <- ensure_vote_context(event, participant, ballot),
         :ok <- ensure_option_context(ballot, option),
         :ok <- ensure_active_participant(participant),
         :ok <- ensure_event_accepts_votes(event),
         :ok <- ensure_ballot_open(ballot) do
      case get_active_option_vote(event, participant, ballot, option) do
        %Vote{} = vote ->
          vote
          |> Repo.delete()
          |> broadcast_result(event.id)

        nil ->
          create_public_vote(event, participant, ballot, %{ballot_option_id: option.id})
      end
    end
  end

  def toggle_public_value_vote(
        %Event{} = event,
        %EventParticipant{} = participant,
        %Ballot{kind: "yes_no_maybe"} = ballot,
        value
      )
      when value in ~w(yes no maybe) do
    with :ok <- ensure_vote_context(event, participant, ballot),
         :ok <- ensure_active_participant(participant),
         :ok <- ensure_event_accepts_votes(event),
         :ok <- ensure_ballot_open(ballot) do
      case get_active_value_vote(event, participant, ballot) do
        %Vote{value: ^value} = vote ->
          vote
          |> Repo.delete()
          |> broadcast_result(event.id)

        %Vote{} = vote ->
          with {:ok, _vote} <- Repo.delete(vote) do
            create_public_vote(event, participant, ballot, %{value: value})
          end

        nil ->
          create_public_vote(event, participant, ballot, %{value: value})
      end
    end
  end

  def toggle_public_value_vote(%Event{}, %EventParticipant{}, %Ballot{}, _value),
    do: {:error, :invalid_vote}

  def reject_vote(%Scope{} = scope, %Vote{} = vote, attrs) do
    event = get_event!(scope, vote.event_id)

    with :ok <- authorize_event_management(scope, event) do
      vote
      |> Vote.reject_changeset(scope.user.id, attrs)
      |> Repo.update()
      |> broadcast_result(event.id)
    end
  end

  def delete_vote(%Scope{} = scope, %Event{} = event, vote_id) do
    with :ok <- authorize_event_management(scope, event),
         :ok <- ensure_event_editable(event),
         %Vote{} = vote <- Repo.get_by(Vote, id: vote_id, event_id: event.id) do
      vote
      |> Repo.delete()
      |> broadcast_result(event.id)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_participant_votes(%Scope{} = scope, %Event{} = event, participant_id) do
    with :ok <- authorize_event_management(scope, event),
         :ok <- ensure_event_editable(event),
         %EventParticipant{} <-
           Repo.get_by(EventParticipant, id: participant_id, event_id: event.id) do
      Vote
      |> where(event_id: ^event.id, participant_id: ^participant_id)
      |> Repo.delete_all()

      broadcast_event(event.id)
      {:ok, :deleted}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_ballot_for_event!(%Event{} = event, id) do
    Ballot
    |> where(event_id: ^event.id)
    |> preload(:options)
    |> Repo.get!(id)
  end

  def get_ballot_option_for_ballot!(%Ballot{} = ballot, id) do
    BallotOption
    |> where(ballot_id: ^ballot.id)
    |> Repo.get!(id)
  end

  def vote_counts(%Ballot{kind: "yes_no_maybe", votes: votes}) do
    votes
    |> Enum.reject(& &1.rejected_at)
    |> Enum.frequencies_by(& &1.value)
  end

  def vote_counts(%Ballot{options: options, votes: votes}) do
    counts =
      votes
      |> Enum.reject(& &1.rejected_at)
      |> Enum.frequencies_by(& &1.ballot_option_id)

    Map.new(options, fn option -> {option.id, Map.get(counts, option.id, 0)} end)
  end

  def subscribe_event(%Event{id: event_id}) do
    Phoenix.PubSub.subscribe(Escalimetro.PubSub, topic(event_id))
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

  defp ensure_ballot_accepts_suggestions(%Ballot{allow_sugestion: true}), do: :ok
  defp ensure_ballot_accepts_suggestions(%Ballot{}), do: {:error, :suggestions_disabled}

  defp ensure_active_participant(%EventParticipant{status: "active"}), do: :ok
  defp ensure_active_participant(%EventParticipant{}), do: {:error, :invalidated_participant}

  defp ensure_vote_matches_ballot(%Ballot{kind: "yes_no_maybe"}, attrs) do
    if get_param(attrs, :value, "value") do
      :ok
    else
      {:error, :invalid_vote}
    end
  end

  defp ensure_vote_matches_ballot(%Ballot{kind: "multiple_choice"}, attrs) do
    if get_param(attrs, :ballot_option_id, "ballot_option_id") do
      :ok
    else
      {:error, :invalid_vote}
    end
  end

  defp ensure_vote_context(%Event{id: event_id}, %EventParticipant{event_id: event_id}, %Ballot{
         event_id: event_id
       }) do
    :ok
  end

  defp ensure_vote_context(_event, _participant, _ballot), do: {:error, :invalid_vote_context}

  defp ensure_option_context(%Ballot{id: ballot_id}, %BallotOption{ballot_id: ballot_id}), do: :ok
  defp ensure_option_context(%Ballot{}, %BallotOption{}), do: {:error, :invalid_vote_context}

  defp get_active_option_vote(
         %Event{id: event_id},
         %EventParticipant{id: participant_id},
         %Ballot{id: ballot_id},
         %BallotOption{id: option_id}
       ) do
    Repo.one(
      from vote in Vote,
        where:
          vote.event_id == ^event_id and
            vote.participant_id == ^participant_id and
            vote.ballot_id == ^ballot_id and
            vote.ballot_option_id == ^option_id and
            is_nil(vote.rejected_at)
    )
  end

  defp get_active_value_vote(
         %Event{id: event_id},
         %EventParticipant{id: participant_id},
         %Ballot{id: ballot_id}
       ) do
    Repo.one(
      from vote in Vote,
        where:
          vote.event_id == ^event_id and
            vote.participant_id == ^participant_id and
            vote.ballot_id == ^ballot_id and
            is_nil(vote.ballot_option_id) and
            is_nil(vote.rejected_at)
    )
  end

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

  defp get_param(%{} = params, atom_key, string_key) do
    Map.get(params, string_key) || Map.get(params, atom_key)
  end

  defp broadcast_result({:ok, struct}, event_id) do
    broadcast_event(event_id)
    {:ok, struct}
  end

  defp broadcast_result({:error, reason}, _event_id), do: {:error, reason}

  defp broadcast_event(event_id) do
    Endpoint.broadcast(topic(event_id), "event_updated", %{})
  end

  defp topic(event_id), do: "events:#{event_id}"
end
