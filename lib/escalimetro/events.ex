defmodule Escalimetro.Events do
  @moduledoc """
  Event management, ballots, participants and votes.
  """

  import Ecto.Query, warn: false

  alias Ecto.{Changeset, Multi}
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
    end
  end

  def close_ballot(%Scope{} = scope, %Ballot{} = ballot) do
    event = get_event!(scope, ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      ballot
      |> Ballot.close_changeset(DateTime.utc_now(:second))
      |> Repo.update()
    end
  end

  def reopen_ballot(%Scope{} = scope, %Ballot{} = ballot) do
    event = get_event!(scope, ballot.event_id)

    with :ok <- ensure_event_editable(event) do
      ballot
      |> Ballot.reopen_changeset()
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

  def suggest_ballot_option(
        %Event{} = event,
        %EventParticipant{} = participant,
        %Ballot{} = ballot,
        attrs
      ) do
    with :ok <- ensure_vote_context(event, participant, ballot),
         :ok <- ensure_event_accepts_votes(event),
         :ok <- ensure_ballot_open(ballot),
         :ok <- ensure_ballot_allows_suggestions(ballot),
         :ok <- ensure_participant_active(participant) do
      %BallotOption{ballot_id: ballot.id, suggested_by_participant_id: participant.id}
      |> BallotOption.changeset(attrs)
      |> Repo.insert()
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
        {:ok, %{participant: participant}} -> {:ok, participant}
        {:error, _operation, changeset, _changes} -> {:error, changeset}
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

  def reject_vote(%Scope{} = scope, %Vote{} = vote, attrs) do
    event = get_event!(scope, vote.event_id)

    with :ok <- authorize_event_management(scope, event),
         :ok <- ensure_event_editable(event) do
      vote
      |> Vote.reject_changeset(scope.user.id, attrs)
      |> Repo.update()
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

  defp active_participant_votes_query(participant_id) do
    from vote in Vote,
      where: vote.participant_id == ^participant_id and is_nil(vote.rejected_at)
  end

  defp ordered_ballot_options_query do
    from option in BallotOption,
      order_by: [asc: option.position, asc: option.inserted_at]
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
end
