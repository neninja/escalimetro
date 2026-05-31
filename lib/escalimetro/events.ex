defmodule Escalimetro.Events do
  @moduledoc """
  Event management, ballots, participants and votes.
  """

  import Ecto.Query, warn: false

  alias Ecto.{Changeset, Multi}
  alias Escalimetro.Accounts.{Scope, User}

  alias Escalimetro.Events.{
    Ballot,
    BallotOption,
    Event,
    EventAdmin,
    EventInvite,
    EventParticipant,
    Topics,
    Vote
  }

  alias Escalimetro.Repo

  @pubsub Escalimetro.PubSub

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
        {:ok, %{event: event}} ->
          broadcast_event(event.id, :event_completed)
          {:ok, event}

        {:error, _operation, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  def subscribe_event(%Event{id: event_id}), do: subscribe_event(event_id)

  def subscribe_event(event_id) do
    Phoenix.PubSub.subscribe(@pubsub, event_topic(event_id))
  end

  def get_participant_event!(participant_token) when is_binary(participant_token) do
    participant =
      EventParticipant
      |> where(participant_token: ^participant_token)
      |> preload([:user, :event])
      |> Repo.one!()

    event = participant.event
    ballots = list_public_ballots(event)
    votes = list_participant_votes(participant)

    %{
      event: event,
      participant: participant,
      ballots: ballots,
      votes: votes,
      votes_by_ballot: Map.new(votes, &{&1.ballot_id, &1})
    }
  end

  ## Invites

  def get_active_event_invite(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      event.id
      |> active_event_invites_query()
      |> preload([:created_by_user])
      |> Repo.one()
    end
  end

  def get_active_invite_by_token(token) when is_binary(token) do
    token_hash = hash_invite_token(token)

    EventInvite
    |> where(token_hash: ^token_hash, status: "active")
    |> where([invite], is_nil(invite.invalidated_at))
    |> preload([:event, :created_by_user])
    |> Repo.one()
  end

  def get_active_invite_by_token(_token), do: nil

  def rotate_event_invite(%Scope{} = scope, %Event{} = event) do
    with :ok <- authorize_event_management(scope, event) do
      token = generate_invite_token()
      now = DateTime.utc_now(:second)

      Multi.new()
      |> Multi.update_all(:old_invites, active_event_invites_query(event.id),
        set: [status: "invalidated", invalidated_at: now, updated_at: now]
      )
      |> Multi.insert(
        :invite,
        EventInvite.changeset(
          %EventInvite{event_id: event.id, created_by_user_id: scope.user.id},
          %{token_hash: hash_invite_token(token), status: "active"}
        )
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{invite: invite}} -> {:ok, %{invite | token: token}}
        {:error, _operation, changeset, _changes} -> {:error, changeset}
      end
    end
  end

  def invalidate_event_invite(%Scope{} = scope, %Event{} = event) do
    with :ok <- authorize_event_management(scope, event) do
      case get_active_event_invite(scope, event) do
        nil ->
          {:ok, nil}

        %EventInvite{} = invite ->
          invite
          |> EventInvite.invalidate_changeset(DateTime.utc_now(:second))
          |> Repo.update()
      end
    end
  end

  def change_guest_identification(attrs \\ %{}) do
    %EventParticipant{
      event_id: -1,
      participant_token: "temporary",
      kind: "guest",
      status: "active"
    }
    |> EventParticipant.changeset(normalize_guest_identification_attrs(attrs))
  end

  def enter_event_invite(scope, invite, attrs \\ %{})

  def enter_event_invite(scope, %EventInvite{id: invite_id}, attrs) do
    invite =
      EventInvite
      |> Repo.get!(invite_id)
      |> Repo.preload(:event)

    with :ok <- ensure_invite_active(invite) do
      case scope do
        %Scope{user: %User{} = user} ->
          enter_authenticated_invite(invite, user)

        _scope ->
          enter_guest_invite(invite, attrs)
      end
    end
  end

  def enter_event_invite(_scope, _invite, _attrs), do: {:error, :invalid_invite}

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
      |> preload(options: ^ordered_ballot_options_query())
      |> Repo.all()
    else
      []
    end
  end

  def get_ballot!(%Scope{} = scope, %Event{} = event, id) do
    _event = get_event!(scope, event.id)

    Ballot
    |> where(event_id: ^event.id)
    |> preload(options: ^ordered_ballot_options_query())
    |> Repo.get!(id)
  end

  def change_ballot(%Scope{} = _scope, %Ballot{} = ballot, attrs \\ %{}) do
    Ballot.changeset(ballot, attrs)
  end

  def create_ballot(%Scope{} = scope, %Event{} = event, attrs) do
    with :ok <- authorize_event_management(scope, event),
         :ok <- ensure_event_editable(event) do
      attrs = normalize_ballot_attrs(attrs)
      option_attrs = ballot_option_attrs(attrs)

      %Ballot{event_id: event.id}
      |> Ballot.changeset(ballot_attrs(attrs))
      |> validate_ballot_options(option_attrs, 0)
      |> insert_ballot_with_options(option_attrs)
      |> broadcast_result(event.id, :ballot_saved)
    end
  end

  def update_ballot(%Scope{} = scope, %Ballot{} = ballot, attrs) do
    event = get_event!(scope, ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      ballot = Repo.preload(ballot, :options)
      attrs = normalize_ballot_attrs(attrs)
      option_attrs = ballot_option_attrs(attrs)
      existing_options_count = Enum.count(ballot.options, &is_nil(&1.rejected_at))

      ballot
      |> Ballot.changeset(ballot_attrs(attrs))
      |> validate_ballot_options(option_attrs, existing_options_count)
      |> update_ballot_with_options(option_attrs)
      |> broadcast_result(event.id, :ballot_saved)
    end
  end

  def close_ballot(%Scope{} = scope, %Ballot{} = ballot) do
    event = get_event!(scope, ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      ballot
      |> Ballot.close_changeset(DateTime.utc_now(:second))
      |> Repo.update()
      |> broadcast_result(event.id, :ballot_closed)
    end
  end

  def reopen_ballot(%Scope{} = scope, %Ballot{} = ballot) do
    event = get_event!(scope, ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      ballot
      |> Ballot.reopen_changeset()
      |> Repo.update()
      |> broadcast_result(event.id, :ballot_reopened)
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
      |> broadcast_result(event.id, :option_saved)
    end
  end

  def suggest_ballot_option(
        %Event{} = _event,
        %EventParticipant{} = participant,
        %Ballot{} = ballot,
        attrs
      ) do
    suggest_option(participant, ballot, attrs)
  end

  def suggest_option(%EventParticipant{} = participant, %Ballot{} = ballot, attrs) do
    participant = Repo.get!(EventParticipant, participant.id)
    event = participant_event!(participant)
    ballot = Repo.preload(ballot, :event)

    with :ok <- ensure_vote_context(event, participant, ballot),
         :ok <- ensure_event_accepts_votes(event),
         :ok <- ensure_ballot_open(ballot),
         :ok <- ensure_ballot_allows_suggestions(ballot),
         :ok <- ensure_participant_active(participant) do
      %BallotOption{ballot_id: ballot.id, suggested_by_participant_id: participant.id}
      |> BallotOption.changeset(normalize_suggestion_attrs(attrs))
      |> validate_unique_normalized_option(ballot.id)
      |> Repo.insert()
      |> broadcast_result(event.id, :option_suggested)
    end
  end

  def reject_ballot_option(%Scope{} = scope, %BallotOption{} = option) do
    option = Repo.preload(option, :ballot)
    event = get_event!(scope, option.ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      now = DateTime.utc_now(:second)

      Multi.new()
      |> Multi.update(:option, BallotOption.reject_changeset(option, now))
      |> Multi.update_all(:votes, active_option_votes_query(option.id),
        set: [
          rejected_at: now,
          rejected_by_user_id: scope.user.id,
          rejection_reason: "Opcao rejeitada",
          updated_at: now
        ]
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{option: option}} ->
          broadcast_event(event.id, :option_rejected)
          {:ok, option}

        {:error, _operation, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  ## Participants

  def list_participants(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      participants =
        EventParticipant
        |> where(event_id: ^event.id)
        |> preload(:user)
        |> order_by([p],
          asc: p.status,
          asc_nulls_last: p.display_name,
          asc: p.inserted_at
        )
        |> Repo.all()

      vote_counts = participant_vote_counts(event.id)

      Enum.map(participants, fn participant ->
        counts = Map.get(vote_counts, participant.id, %{accepted: 0, rejected: 0})

        %{
          participant
          | accepted_votes_count: counts.accepted,
            rejected_votes_count: counts.rejected,
            total_votes_count: counts.accepted + counts.rejected
        }
      end)
    else
      []
    end
  end

  def list_event_participants(%Scope{} = scope, %Event{} = event),
    do: list_participants(scope, event)

  def change_event_participant(
        %Scope{} = _scope,
        %EventParticipant{} = event_participant,
        attrs \\ %{}
      ) do
    EventParticipant.changeset(event_participant, attrs)
  end

  def create_event_participant(%Scope{} = scope, %Event{} = event, attrs) do
    with :ok <- authorize_event_management(scope, event) do
      %EventParticipant{event_id: event.id, participant_token: generate_participant_token()}
      |> EventParticipant.changeset(attrs)
      |> Repo.insert()
    end
  end

  def create_user_participant(%Scope{} = scope, %Event{} = event, %User{} = user, attrs \\ %{}) do
    with :ok <- authorize_event_management(scope, event) do
      attrs = put_param(attrs, :kind, "kind", "user")

      %EventParticipant{
        event_id: event.id,
        user_id: user.id,
        participant_token: generate_participant_token()
      }
      |> EventParticipant.changeset(attrs)
      |> Repo.insert()
    end
  end

  def invalidate_participant(%Scope{} = scope, %EventParticipant{} = participant) do
    event = get_event!(scope, participant.event_id)

    with :ok <- ensure_event_editable(event) do
      now = DateTime.utc_now(:second)

      Multi.new()
      |> Multi.update(:participant, EventParticipant.invalidate_changeset(participant, now))
      |> Multi.update_all(:votes, active_participant_votes_query(participant.id),
        set: [
          rejected_at: now,
          rejected_by_user_id: scope.user.id,
          rejection_reason: "Participante invalidado",
          updated_at: now
        ]
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{participant: participant}} ->
          broadcast_event(event.id, :participant_invalidated)
          {:ok, participant}

        {:error, _operation, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  ## Votes

  def list_votes(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      Vote
      |> where(event_id: ^event.id)
      |> order_by([v], desc: v.inserted_at)
      |> preload([:ballot, :ballot_option, :rejected_by_user, participant: :user])
      |> Repo.all()
    else
      []
    end
  end

  def list_suggested_options(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      BallotOption
      |> join(:inner, [o], b in assoc(o, :ballot))
      |> where([o, b], b.event_id == ^event.id and not is_nil(o.suggested_by_participant_id))
      |> order_by([o, b], desc: o.inserted_at)
      |> preload([o, b], [:suggested_by_participant, ballot: b])
      |> Repo.all()
    else
      []
    end
  end

  ## Results

  def get_event_results(%Scope{} = scope, %Event{} = event) do
    if can_manage_event?(scope, event) do
      ballot_results =
        event
        |> list_result_ballots()
        |> build_ballot_results(list_result_votes(event))

      %{
        event: event,
        ballot_results: ballot_results,
        ballots_count: length(ballot_results),
        active_votes_count: sum_result_count(ballot_results, :active_votes_count),
        rejected_votes_count: sum_result_count(ballot_results, :rejected_votes_count)
      }
      |> put_event_results_summary()
    else
      empty_event_results(event)
    end
  end

  def get_event_results(_scope, %Event{} = event), do: empty_event_results(event)

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
         :ok <- ensure_ballot_open(ballot),
         :ok <- ensure_participant_active(participant) do
      %Vote{event_id: event.id, ballot_id: ballot.id, participant_id: participant.id}
      |> Vote.changeset(attrs)
      |> Repo.insert()
    end
  end

  def cast_vote(%EventParticipant{} = participant, %Ballot{} = ballot, attrs) do
    participant = Repo.get!(EventParticipant, participant.id)
    event = participant_event!(participant)
    ballot = Repo.preload(ballot, [:event, :options])

    with :ok <- ensure_vote_context(event, participant, ballot),
         :ok <- ensure_event_accepts_votes(event),
         :ok <- ensure_ballot_open(ballot),
         :ok <- ensure_participant_active(participant),
         {:ok, vote_attrs} <- normalize_vote_attrs(ballot, attrs) do
      upsert_participant_vote(event, participant, ballot, vote_attrs)
      |> broadcast_result(event.id, :vote_cast)
    end
  end

  def reject_vote(%Scope{} = scope, %Vote{} = vote, attrs) do
    event = get_event!(scope, vote.event_id)

    with :ok <- authorize_event_management(scope, event),
         :ok <- ensure_event_editable(event) do
      vote
      |> Vote.reject_changeset(scope.user.id, attrs)
      |> Repo.update()
      |> broadcast_result(event.id, :vote_rejected)
    end
  end

  def restore_vote(%Scope{} = scope, %Vote{} = vote) do
    event = get_event!(scope, vote.event_id)
    participant = Repo.get!(EventParticipant, vote.participant_id)

    with :ok <- authorize_event_management(scope, event),
         :ok <- ensure_event_editable(event),
         :ok <- ensure_participant_active(participant) do
      vote
      |> Vote.restore_changeset()
      |> Repo.update()
      |> broadcast_result(event.id, :vote_restored)
    end
  end

  defp list_public_ballots(%Event{id: event_id}) do
    Ballot
    |> where(event_id: ^event_id)
    |> order_by([b], asc: b.position, asc: b.inserted_at)
    |> preload(options: ^public_ballot_options_query())
    |> Repo.all()
  end

  defp list_participant_votes(%EventParticipant{id: participant_id, event_id: event_id}) do
    Vote
    |> where(participant_id: ^participant_id, event_id: ^event_id)
    |> order_by([v], desc: is_nil(v.rejected_at), desc: v.updated_at)
    |> distinct([v], v.ballot_id)
    |> preload([:ballot_option])
    |> Repo.all()
  end

  defp participant_event!(%EventParticipant{event: %Event{} = event}), do: event

  defp participant_event!(%EventParticipant{event_id: event_id}) do
    Repo.get!(Event, event_id)
  end

  defp ensure_invite_active(%EventInvite{status: "active", invalidated_at: nil}), do: :ok
  defp ensure_invite_active(%EventInvite{}), do: {:error, :invalid_invite}

  defp enter_authenticated_invite(%EventInvite{event: %Event{} = event}, %User{} = user) do
    case get_user_event_participant(event, user) do
      %EventParticipant{} = participant ->
        {:ok, participant}

      nil ->
        create_invite_user_participant(event, user)
    end
  end

  defp enter_guest_invite(%EventInvite{event: %Event{} = event}, attrs) do
    attrs = normalize_guest_identification_attrs(attrs)

    changeset = change_guest_identification(attrs)

    if changeset.valid? do
      display_name = Changeset.get_field(changeset, :display_name)

      case get_guest_event_participant(event, display_name) do
        %EventParticipant{} = participant ->
          {:ok, participant}

        nil ->
          create_invite_guest_participant(event, display_name)
      end
    else
      {:error, changeset}
    end
  end

  defp get_user_event_participant(%Event{id: event_id}, %User{id: user_id}) do
    EventParticipant
    |> where(event_id: ^event_id, user_id: ^user_id, kind: "user")
    |> Repo.one()
  end

  defp create_invite_user_participant(%Event{id: event_id}, %User{} = user) do
    %EventParticipant{
      event_id: event_id,
      user_id: user.id,
      participant_token: generate_participant_token()
    }
    |> EventParticipant.changeset(%{
      kind: "user",
      display_name: user.email,
      status: "active"
    })
    |> Repo.insert()
  end

  defp get_guest_event_participant(%Event{id: event_id}, display_name) do
    EventParticipant
    |> where(event_id: ^event_id, kind: "guest", display_name: ^display_name)
    |> order_by([participant], asc: participant.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp create_invite_guest_participant(%Event{id: event_id}, display_name) do
    %EventParticipant{event_id: event_id, participant_token: generate_participant_token()}
    |> EventParticipant.changeset(%{
      kind: "guest",
      display_name: display_name,
      status: "active"
    })
    |> Repo.insert()
  end

  defp normalize_guest_identification_attrs(%{} = attrs) do
    display_name =
      attrs
      |> fetch_param(:display_name, "display_name")
      |> value_or("")
      |> to_string()
      |> String.trim()

    put_param(attrs, :display_name, "display_name", display_name)
  end

  defp normalize_guest_identification_attrs(attrs), do: attrs

  defp normalize_vote_attrs(%Ballot{kind: "multiple_choice"} = ballot, attrs) do
    option_id =
      attrs
      |> fetch_param(:ballot_option_id, "ballot_option_id")
      |> value_or(nil)
      |> parse_optional_integer()

    if valid_ballot_option?(ballot, option_id) do
      {:ok,
       %{
         ballot_option_id: option_id,
         value: nil,
         intensity: vote_intensity(attrs),
         justification: vote_justification(attrs)
       }}
    else
      {:error, :invalid_ballot_option}
    end
  end

  defp normalize_vote_attrs(%Ballot{kind: "yes_no_maybe"}, attrs) do
    value =
      attrs
      |> fetch_param(:value, "value")
      |> value_or(nil)

    if value in Vote.values() do
      {:ok,
       %{
         ballot_option_id: nil,
         value: value,
         intensity: false,
         justification: vote_justification(attrs)
       }}
    else
      {:error, :invalid_vote_value}
    end
  end

  defp vote_intensity(attrs) do
    attrs
    |> fetch_param(:intensity, "intensity")
    |> value_or(false)
    |> cast_boolean(false)
  end

  defp vote_justification(attrs) do
    attrs
    |> fetch_param(:justification, "justification")
    |> value_or(nil)
  end

  defp valid_ballot_option?(%Ballot{id: ballot_id}, option_id) when is_integer(option_id) do
    Repo.exists?(
      from option in BallotOption,
        where:
          option.id == ^option_id and option.ballot_id == ^ballot_id and
            is_nil(option.rejected_at)
    )
  end

  defp valid_ballot_option?(_ballot, _option_id), do: false

  defp upsert_participant_vote(event, participant, ballot, vote_attrs) do
    Repo.transaction(fn ->
      active_votes =
        Vote
        |> where(
          event_id: ^event.id,
          ballot_id: ^ballot.id,
          participant_id: ^participant.id
        )
        |> where([v], is_nil(v.rejected_at))
        |> order_by([v], asc: v.inserted_at)
        |> Repo.all()

      [vote | stale_votes] = active_votes ++ [nil]
      reject_stale_votes(stale_votes)

      result =
        case vote do
          nil ->
            %Vote{event_id: event.id, ballot_id: ballot.id, participant_id: participant.id}
            |> Vote.changeset(vote_attrs)
            |> Repo.insert()

          %Vote{} = vote ->
            vote
            |> Vote.changeset(vote_attrs)
            |> Repo.update()
        end

      case result do
        {:ok, vote} -> vote
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp reject_stale_votes(votes) do
    now = DateTime.utc_now(:second)

    votes
    |> Enum.reject(&is_nil/1)
    |> Enum.each(fn vote ->
      vote
      |> Changeset.change(rejected_at: now, rejection_reason: "Voto substituido")
      |> Repo.update!()
    end)
  end

  defp normalize_suggestion_attrs(attrs) do
    label =
      attrs
      |> fetch_param(:label, "label")
      |> value_or("")
      |> to_string()
      |> String.trim()

    put_param(attrs, :label, "label", label)
  end

  defp validate_unique_normalized_option(%Changeset{} = changeset, ballot_id) do
    label = Changeset.get_field(changeset, :label)

    if label && normalized_option_exists?(ballot_id, label) do
      Changeset.add_error(changeset, :label, "has already been suggested")
    else
      changeset
    end
  end

  defp normalized_option_exists?(ballot_id, label) do
    normalized_label = normalize_label(label)

    BallotOption
    |> where(ballot_id: ^ballot_id)
    |> where([o], is_nil(o.rejected_at))
    |> select([o], o.label)
    |> Repo.all()
    |> Enum.any?(&(normalize_label(&1) == normalized_label))
  end

  defp normalize_label(label) do
    label
    |> to_string()
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp list_result_ballots(%Event{id: event_id}) do
    Ballot
    |> where(event_id: ^event_id)
    |> order_by([b], asc: b.position, asc: b.inserted_at)
    |> preload(options: ^ordered_ballot_options_query())
    |> Repo.all()
  end

  defp list_result_votes(%Event{id: event_id}) do
    Vote
    |> where(event_id: ^event_id)
    |> order_by([v], asc: v.inserted_at)
    |> preload([:ballot_option, participant: :user])
    |> Repo.all()
  end

  defp build_ballot_results(ballots, votes) do
    votes_by_ballot = Enum.group_by(votes, & &1.ballot_id)

    Enum.map(ballots, fn ballot ->
      build_ballot_result(ballot, Map.get(votes_by_ballot, ballot.id, []))
    end)
  end

  defp build_ballot_result(%Ballot{kind: "multiple_choice"} = ballot, votes) do
    active_votes = Enum.filter(votes, &active_result_vote?/1)
    active_votes_count = length(active_votes)

    option_results =
      ballot.options
      |> Enum.map(&multiple_choice_option_result(&1, votes, active_votes_count))
      |> sort_option_results()
      |> mark_winner(active_votes_count)

    %{
      ballot: ballot,
      option_results: option_results,
      winner: Enum.find(option_results, & &1.winner),
      active_votes_count: active_votes_count,
      rejected_votes_count: length(votes) - active_votes_count,
      rejected_vote_results: rejected_vote_results(votes)
    }
  end

  defp build_ballot_result(%Ballot{kind: "yes_no_maybe"} = ballot, votes) do
    active_votes = Enum.filter(votes, &active_result_vote?/1)
    active_votes_count = length(active_votes)

    option_results =
      yes_no_maybe_result_values()
      |> Enum.map(fn {value, label, position} ->
        yes_no_maybe_option_result(value, label, position, votes, active_votes_count)
      end)
      |> sort_option_results()
      |> mark_winner(active_votes_count)

    %{
      ballot: ballot,
      option_results: option_results,
      winner: Enum.find(option_results, & &1.winner),
      active_votes_count: active_votes_count,
      rejected_votes_count: length(votes) - active_votes_count,
      rejected_vote_results: rejected_vote_results(votes)
    }
  end

  defp multiple_choice_option_result(%BallotOption{} = option, votes, active_votes_count) do
    option_votes = Enum.filter(votes, &(&1.ballot_option_id == option.id))
    active_votes = Enum.filter(option_votes, &active_result_vote?/1)
    votes_count = length(active_votes)

    %{
      key: "option-#{option.id}",
      label: option.label,
      position: option.position,
      votes_count: votes_count,
      intensity_count: Enum.count(active_votes, & &1.intensity),
      rejected_votes_count: length(option_votes) - votes_count,
      percent: vote_percent(votes_count, active_votes_count),
      suggested: not is_nil(option.suggested_by_participant_id),
      rejected: not is_nil(option.rejected_at),
      winner: false
    }
  end

  defp yes_no_maybe_option_result(value, label, position, votes, active_votes_count) do
    option_votes = Enum.filter(votes, &(&1.value == value))
    active_votes = Enum.filter(option_votes, &active_result_vote?/1)
    votes_count = length(active_votes)

    %{
      key: "value-#{value}",
      label: label,
      position: position,
      votes_count: votes_count,
      intensity_count: 0,
      rejected_votes_count: length(option_votes) - votes_count,
      percent: vote_percent(votes_count, active_votes_count),
      suggested: false,
      rejected: false,
      winner: false
    }
  end

  defp sort_option_results(option_results) do
    Enum.sort_by(option_results, fn option ->
      {-option.votes_count, -option.intensity_count, option.position,
       normalize_label(option.label)}
    end)
  end

  defp mark_winner(option_results, 0), do: option_results

  defp mark_winner([winner | rest], _active_votes_count) do
    [%{winner | winner: true} | rest]
  end

  defp mark_winner([], _active_votes_count), do: []

  defp rejected_vote_results(votes) do
    votes
    |> Enum.reject(&active_result_vote?/1)
    |> Enum.map(fn vote ->
      %{
        id: vote.id,
        participant_name: result_participant_name(vote.participant),
        value_label: result_vote_label(vote),
        reason: vote.rejection_reason || "Sem motivo informado"
      }
    end)
  end

  defp active_result_vote?(%Vote{
         rejected_at: nil,
         participant: %EventParticipant{status: "active"},
         ballot_option: nil
       }),
       do: true

  defp active_result_vote?(%Vote{
         rejected_at: nil,
         participant: %EventParticipant{status: "active"},
         ballot_option: %BallotOption{rejected_at: nil}
       }),
       do: true

  defp active_result_vote?(_vote), do: false

  defp result_participant_name(%EventParticipant{kind: "user", user: %User{email: email}}),
    do: email

  defp result_participant_name(%EventParticipant{display_name: display_name})
       when is_binary(display_name),
       do: display_name

  defp result_participant_name(_participant), do: "Participante"

  defp result_vote_label(%Vote{ballot_option: %BallotOption{label: label}}), do: label
  defp result_vote_label(%Vote{value: value}), do: result_value_label(value)

  defp result_value_label("yes"), do: "Sim"
  defp result_value_label("no"), do: "Nao"
  defp result_value_label("maybe"), do: "Talvez"
  defp result_value_label(_value), do: "Valor nao informado"

  defp yes_no_maybe_result_values do
    [{"yes", "Sim", 0}, {"no", "Nao", 1}, {"maybe", "Talvez", 2}]
  end

  defp vote_percent(_votes_count, 0), do: 0

  defp vote_percent(votes_count, active_votes_count) do
    round(votes_count * 100 / active_votes_count)
  end

  defp sum_result_count(ballot_results, key) do
    ballot_results
    |> Enum.map(&Map.fetch!(&1, key))
    |> Enum.sum()
  end

  defp empty_event_results(event) do
    %{
      event: event,
      ballot_results: [],
      ballots_count: 0,
      active_votes_count: 0,
      rejected_votes_count: 0
    }
    |> put_event_results_summary()
  end

  defp put_event_results_summary(%{event: event, ballot_results: ballot_results} = results) do
    Map.put(results, :summary, event_results_summary(event, ballot_results))
  end

  defp event_results_summary(%Event{} = event, ballot_results) do
    header =
      ["Resultado do evento #{event.title}"]
      |> maybe_append_summary_line(event.location, "Local")
      |> maybe_append_summary_line(summary_datetime(event.scheduled_at), "Data")

    ballot_lines = Enum.map(ballot_results, &ballot_result_summary_line/1)

    Enum.join(header ++ [""] ++ ballot_lines, "\n")
  end

  defp maybe_append_summary_line(lines, nil, _label), do: lines
  defp maybe_append_summary_line(lines, "", _label), do: lines
  defp maybe_append_summary_line(lines, value, label), do: lines ++ ["#{label}: #{value}"]

  defp summary_datetime(nil), do: nil

  defp summary_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%d/%m/%Y %H:%M")
  end

  defp ballot_result_summary_line(%{ballot: ballot, winner: nil} = result) do
    "- #{ballot.title}: sem votos ativos#{summary_rejected_suffix(result)}"
  end

  defp ballot_result_summary_line(%{ballot: ballot, winner: winner} = result) do
    details =
      ["#{winner.votes_count} voto(s)"]
      |> maybe_append_intensity_detail(winner.intensity_count)

    "- #{ballot.title}: #{winner.label} (#{Enum.join(details, ", ")})#{summary_rejected_suffix(result)}"
  end

  defp maybe_append_intensity_detail(details, 0), do: details

  defp maybe_append_intensity_detail(details, intensity_count) do
    details ++ ["#{intensity_count} intenso(s)"]
  end

  defp summary_rejected_suffix(%{rejected_votes_count: 0}), do: ""

  defp summary_rejected_suffix(%{rejected_votes_count: rejected_votes_count}) do
    " - #{rejected_votes_count} voto(s) rejeitado(s)"
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

  defp ensure_ballot_allows_suggestions(%Ballot{allow_sugestion: true}), do: :ok
  defp ensure_ballot_allows_suggestions(%Ballot{}), do: {:error, :suggestions_disabled}

  defp ensure_participant_active(%EventParticipant{status: "active"}), do: :ok
  defp ensure_participant_active(%EventParticipant{}), do: {:error, :invalidated_participant}

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

  defp active_event_invites_query(event_id) do
    from invite in EventInvite,
      where:
        invite.event_id == ^event_id and invite.status == "active" and
          is_nil(invite.invalidated_at)
  end

  defp active_participant_votes_query(participant_id) do
    from vote in Vote,
      where: vote.participant_id == ^participant_id and is_nil(vote.rejected_at)
  end

  defp ordered_ballot_options_query do
    from option in BallotOption,
      order_by: [asc: option.position, asc: option.inserted_at]
  end

  defp public_ballot_options_query do
    from option in BallotOption,
      where: is_nil(option.rejected_at),
      order_by: [asc: option.position, asc: option.inserted_at],
      preload: [:suggested_by_participant]
  end

  defp active_option_votes_query(option_id) do
    from vote in Vote,
      where: vote.ballot_option_id == ^option_id and is_nil(vote.rejected_at)
  end

  defp normalize_ballot_attrs(%{} = attrs) do
    attrs
    |> normalize_ballot_status()
    |> normalize_ballot_position()
  end

  defp normalize_ballot_attrs(attrs), do: attrs

  defp normalize_ballot_status(attrs) do
    case fetch_param(attrs, :status, "status") do
      {:ok, ""} -> delete_param(attrs, :status, "status")
      _ -> attrs
    end
  end

  defp normalize_ballot_position(attrs) do
    case fetch_param(attrs, :position, "position") do
      {:ok, ""} -> delete_param(attrs, :position, "position")
      _ -> attrs
    end
  end

  defp ballot_attrs(%{} = attrs), do: delete_param(attrs, :options, "options")

  defp ballot_option_attrs(%{} = attrs) do
    case fetch_param(attrs, :options, "options") do
      {:ok, options} -> normalize_option_attrs(options)
      :error -> :not_provided
    end
  end

  defp validate_ballot_options(%Changeset{} = changeset, option_attrs, existing_options_count) do
    if Changeset.get_field(changeset, :kind) == "multiple_choice" do
      option_count =
        case option_attrs do
          :not_provided -> existing_options_count
          options -> Enum.count(options, &(&1.label != ""))
        end

      if option_count < 2 do
        Changeset.add_error(changeset, :options, "must have at least two options")
      else
        changeset
      end
    else
      changeset
    end
  end

  defp insert_ballot_with_options(%Changeset{valid?: false} = changeset, _option_attrs) do
    {:error, changeset}
  end

  defp insert_ballot_with_options(%Changeset{} = changeset, option_attrs) do
    Multi.new()
    |> Multi.insert(:ballot, changeset)
    |> Multi.run(:options, fn repo, %{ballot: ballot} ->
      sync_ballot_options(repo, ballot, option_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{ballot: ballot}} ->
        {:ok, Repo.preload(ballot, [options: ordered_ballot_options_query()], force: true)}

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp update_ballot_with_options(%Changeset{valid?: false} = changeset, _option_attrs) do
    {:error, changeset}
  end

  defp update_ballot_with_options(%Changeset{} = changeset, option_attrs) do
    Multi.new()
    |> Multi.update(:ballot, changeset)
    |> Multi.run(:options, fn repo, %{ballot: ballot} ->
      sync_ballot_options(repo, ballot, option_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{ballot: ballot}} ->
        {:ok, Repo.preload(ballot, [options: ordered_ballot_options_query()], force: true)}

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp sync_ballot_options(repo, %Ballot{kind: "yes_no_maybe"} = ballot, option_attrs) do
    if option_attrs != :not_provided do
      repo.delete_all(from option in BallotOption, where: option.ballot_id == ^ballot.id)
    end

    {:ok, []}
  end

  defp sync_ballot_options(repo, %Ballot{} = ballot, :not_provided) do
    {:ok,
     repo.all(
       from option in ordered_ballot_options_query(),
         where: option.ballot_id == ^ballot.id
     )}
  end

  defp sync_ballot_options(repo, %Ballot{} = ballot, option_attrs) do
    existing_options =
      repo.all(from option in BallotOption, where: option.ballot_id == ^ballot.id)
      |> Map.new(&{&1.id, &1})

    saved_options =
      option_attrs
      |> Enum.with_index()
      |> Enum.map(fn {option_attrs, index} ->
        attrs = %{label: option_attrs.label, position: option_attrs.position || index}

        case Map.fetch(existing_options, option_attrs.id) do
          {:ok, option} ->
            option
            |> BallotOption.changeset(attrs)
            |> repo.update!()

          :error ->
            %BallotOption{ballot_id: ballot.id}
            |> BallotOption.changeset(attrs)
            |> repo.insert!()
        end
      end)

    saved_ids = Enum.map(saved_options, & &1.id)

    omitted_options_query =
      from option in BallotOption,
        where:
          option.ballot_id == ^ballot.id and is_nil(option.suggested_by_participant_id) and
            option.id not in ^saved_ids

    repo.delete_all(omitted_options_query)

    {:ok, saved_options}
  end

  defp normalize_option_attrs(options) when is_map(options) do
    options
    |> Enum.sort_by(fn {key, _value} -> parse_integer(key, 0) end)
    |> Enum.map(fn {_key, value} -> value end)
    |> normalize_option_attrs()
  end

  defp normalize_option_attrs(options) when is_list(options) do
    options
    |> Enum.with_index()
    |> Enum.map(fn {option, index} -> normalize_option_attr(option, index) end)
    |> Enum.reject(&(&1.label == ""))
  end

  defp normalize_option_attrs(_options), do: []

  defp normalize_option_attr(%{} = option, index) do
    %{
      id: option |> fetch_param(:id, "id") |> value_or(nil) |> parse_optional_integer(),
      label:
        option |> fetch_param(:label, "label") |> value_or("") |> to_string() |> String.trim(),
      position:
        option
        |> fetch_param(:position, "position")
        |> value_or(index)
        |> parse_integer(index)
    }
  end

  defp normalize_option_attr(option, index) when is_binary(option) do
    %{id: nil, label: String.trim(option), position: index}
  end

  defp normalize_option_attr(_option, index), do: %{id: nil, label: "", position: index}

  defp participant_vote_counts(event_id) do
    Vote
    |> where(event_id: ^event_id)
    |> group_by([v], [v.participant_id, fragment("? IS NOT NULL", v.rejected_at)])
    |> select([v], {v.participant_id, fragment("? IS NOT NULL", v.rejected_at), count(v.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {participant_id, rejected?, count}, acc ->
      counts = Map.get(acc, participant_id, %{accepted: 0, rejected: 0})
      key = if rejected?, do: :rejected, else: :accepted
      Map.put(acc, participant_id, Map.put(counts, key, count))
    end)
  end

  defp put_param(%{} = params, atom_key, string_key, value) do
    if Enum.any?(params, fn {key, _value} -> is_binary(key) end) do
      Map.put(params, string_key, value)
    else
      Map.put(params, atom_key, value)
    end
  end

  defp fetch_param(%{} = params, atom_key, string_key) do
    cond do
      Map.has_key?(params, atom_key) -> {:ok, Map.fetch!(params, atom_key)}
      Map.has_key?(params, string_key) -> {:ok, Map.fetch!(params, string_key)}
      true -> :error
    end
  end

  defp delete_param(%{} = params, atom_key, string_key) do
    params
    |> Map.delete(atom_key)
    |> Map.delete(string_key)
  end

  defp value_or({:ok, value}, _default), do: value
  defp value_or(:error, default), do: default

  defp parse_integer(value, _default) when is_integer(value), do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> default
    end
  end

  defp parse_integer(_value, default), do: default

  defp parse_optional_integer(nil), do: nil
  defp parse_optional_integer(""), do: nil
  defp parse_optional_integer(value), do: parse_integer(value, nil)

  defp generate_invite_token do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp hash_invite_token(token) when is_binary(token) do
    :sha256
    |> :crypto.hash(token)
    |> Base.encode16(case: :lower)
  end

  defp cast_boolean(value, _default) when is_boolean(value), do: value

  defp cast_boolean(value, default) do
    case Ecto.Type.cast(:boolean, value) do
      {:ok, boolean} -> boolean
      :error -> default
    end
  end

  defp generate_participant_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp event_topic(event_id), do: Topics.event(event_id)

  defp broadcast_result({:ok, %{id: event_id} = result}, _event_id, event_name)
       when event_name in [:event_completed] do
    broadcast_event(event_id, event_name)
    {:ok, result}
  end

  defp broadcast_result({:ok, result}, event_id, event_name) do
    broadcast_event(event_id, event_name)
    {:ok, result}
  end

  defp broadcast_result(other, _event_id, _event_name), do: other

  defp broadcast_event(event_id, event_name) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      event_topic(event_id),
      {:event_changed, event_name, event_id}
    )
  end
end
