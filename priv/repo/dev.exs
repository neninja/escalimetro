# Script for populating the development database with a realistic scenario.
# You can run it as:
#
#     mix run priv/repo/dev.exs

defmodule Escalimetro.Repo.DevSeed do
  import Ecto.Query

  alias Escalimetro.Accounts
  alias Escalimetro.Accounts.Scope
  alias Escalimetro.Accounts.User
  alias Escalimetro.Events
  alias Escalimetro.Events.{Ballot, BallotOption, Event, EventAdmin, EventParticipant}
  alias Escalimetro.Repo

  @password "devpassword123"
  @sample_event_public_invite_id "11111111-1111-4111-8111-111111111111"

  def run do
    admin =
      ensure_user!("admin@escalimetro.dev",
        password: @password,
        system_admin: true
      )

    users = %{
      rei: ensure_user!("rei@escalimetro.dev", password: @password),
      neni: ensure_user!("neni@escalimetro.dev", password: @password),
    }

    owner_scope = Scope.for_user(users.neni)

    event =
      ensure_event!(owner_scope, %{
        title: "Encontro Presencial",
        description: "Primeiro encontro dos envolvidos para decidir comida e combinados.",
        location: "Sala principal",
        public_invite_id: @sample_event_public_invite_id,
        status: "open"
      })

    ensure_event_admin!(owner_scope, event, admin)

    participants = %{
      rei: ensure_user_participant!(owner_scope, event, users.rei),
      neni: ensure_user_participant!(owner_scope, event, users.neni),
      vitor: ensure_guest_participant!(owner_scope, event, "Vitor")
    }

    pizza_ballot =
      ensure_ballot!(owner_scope, event, %{
        title: "Sabores de pizza",
        description: "Escolha os sabores preferidos para o encontro.",
        kind: "multiple_choice",
        allow_sugestion: true,
        status: "open",
        position: 0,
        options: pizza_options()
      })

    attendance_ballot =
      ensure_ballot!(owner_scope, event, %{
        title: "Voce consegue participar presencialmente?",
        description: "Confirme sua disponibilidade para o encontro.",
        kind: "yes_no_maybe",
        allow_sugestion: false,
        status: "open",
        position: 1
      })

    cast_option_votes!(event, participants.rei, pizza_ballot, [
      "Calabresa",
      "Quatro Queijos"
    ])

    cast_option_votes!(event, participants.neni, pizza_ballot, [
      "Portuguesa",
      "Calabresa"
    ])

    cast_option_votes!(event, participants.vitor, pizza_ballot, [
      "Strogonoff"
    ])

    cast_value_vote!(event, participants.rei, attendance_ballot, "yes")
    cast_value_vote!(event, participants.neni, attendance_ballot, "yes")
    cast_value_vote!(event, participants.vitor, attendance_ballot, "maybe")
  end

  defp ensure_user!(email, opts) do
    password = Keyword.fetch!(opts, :password)
    system_admin = Keyword.get(opts, :system_admin, false)

    user =
      case Accounts.get_user_by_email(email) do
        %User{} = user ->
          user

        nil ->
          {:ok, user} = Accounts.register_user(%{email: email})
          user
      end

    user = confirm_user!(user)
    user = set_password!(user, password)

    user
    |> Ecto.Changeset.change(system_admin: system_admin)
    |> Repo.update!()
  end

  defp confirm_user!(%User{} = user) do
    user
    |> User.confirm_changeset()
    |> Repo.update!()
  end

  defp set_password!(%User{} = user, password) do
    {:ok, {user, _expired_tokens}} = Accounts.update_user_password(user, %{password: password})
    user
  end

  defp ensure_event!(%Scope{} = scope, attrs) do
    event =
      case Repo.get_by(Event, title: attrs.title, owner_user_id: scope.user.id) do
        %Event{} = event ->
          event

        nil ->
          {:ok, event} = Events.create_event(scope, attrs)
          event
      end

    maybe_set_public_invite_id!(event, attrs)
  end

  defp maybe_set_public_invite_id!(%Event{} = event, %{public_invite_id: public_invite_id}) do
    {:ok, public_invite_id} = Ecto.UUID.cast(public_invite_id)

    if event.public_invite_id == public_invite_id do
      event
    else
      event
      |> Ecto.Changeset.change(public_invite_id: public_invite_id)
      |> Repo.update!()
    end
  end

  defp maybe_set_public_invite_id!(%Event{} = event, _attrs), do: event

  defp ensure_event_admin!(%Scope{} = scope, %Event{} = event, %User{} = user) do
    exists? =
      Repo.exists?(
        from admin in EventAdmin,
          where: admin.event_id == ^event.id and admin.user_id == ^user.id
      )

    unless exists? do
      {:ok, _event_admin} = Events.add_event_admin(scope, event, user)
    end
  end

  defp ensure_user_participant!(%Scope{} = scope, %Event{} = event, %User{} = user) do
    case Repo.get_by(EventParticipant, event_id: event.id, user_id: user.id, kind: "user") do
      %EventParticipant{} = participant ->
        participant

      nil ->
        {:ok, participant} =
          Events.create_user_participant(scope, event, user, %{
            display_name: user.email,
            status: "active"
          })

        participant
    end
  end

  defp ensure_guest_participant!(%Scope{} = scope, %Event{} = event, display_name) do
    case Repo.get_by(EventParticipant,
           event_id: event.id,
           display_name: display_name,
           kind: "guest"
         ) do
      %EventParticipant{} = participant ->
        participant

      nil ->
        {:ok, participant} =
          Events.create_event_participant(scope, event, %{
            display_name: display_name,
            kind: "guest",
            status: "active",
            metadata: %{"source" => "seed"}
          })

        participant
    end
  end

  defp ensure_ballot!(%Scope{} = scope, %Event{} = event, attrs) do
    ballot =
      case Repo.get_by(Ballot, event_id: event.id, title: attrs.title) do
        %Ballot{} = ballot ->
          ballot_attrs = Map.drop(attrs, [:options])
          {:ok, ballot} = Events.update_ballot(scope, ballot, ballot_attrs)
          ballot

        nil ->
          {:ok, ballot} = Events.create_ballot(scope, event, attrs)
          ballot
      end

    ensure_ballot_options!(scope, ballot, Map.get(attrs, :options, []))
  end

  defp ensure_ballot_options!(%Scope{} = scope, %Ballot{} = ballot, options) do
    Enum.each(options, fn attrs ->
      unless Repo.exists?(
               from option in BallotOption,
                 where: option.ballot_id == ^ballot.id and option.label == ^attrs.label
             ) do
        {:ok, _option} = Events.create_ballot_option(scope, ballot, attrs)
      end
    end)

    Repo.preload(ballot, :options, force: true)
  end

  defp cast_option_votes!(
         %Event{} = event,
         %EventParticipant{} = participant,
         %Ballot{} = ballot,
         votes
       ) do
    ballot = Repo.preload(ballot, :options, force: true)

    Enum.each(votes, fn label ->
      option = Enum.find(ballot.options, &(&1.label == label))

      existing_vote_query =
        from vote in Escalimetro.Events.Vote,
          where:
            vote.event_id == ^event.id and
              vote.ballot_id == ^ballot.id and
              vote.participant_id == ^participant.id and
              vote.ballot_option_id == ^option.id and
              is_nil(vote.rejected_at)

      if Repo.exists?(existing_vote_query) do
        Repo.update_all(existing_vote_query, set: [justification: nil])
      else
        {:ok, _vote} =
          Events.create_vote(%Scope{}, event, participant, ballot, %{
            ballot_option_id: option.id
          })
      end
    end)
  end

  defp cast_value_vote!(
         %Event{} = event,
         %EventParticipant{} = participant,
         %Ballot{} = ballot,
         value
       ) do
    existing_vote_query =
      from vote in Escalimetro.Events.Vote,
        where:
          vote.event_id == ^event.id and
            vote.ballot_id == ^ballot.id and
            vote.participant_id == ^participant.id and
            is_nil(vote.ballot_option_id) and
            is_nil(vote.rejected_at)

    if Repo.exists?(existing_vote_query) do
      Repo.update_all(existing_vote_query, set: [justification: nil])
    else
      {:ok, _vote} =
        Events.create_vote(%Scope{}, event, participant, ballot, %{
          value: value
        })
    end
  end

  defp pizza_options do
    [
      "Alho e oleo",
      "Americana",
      "Atum",
      "Bacon",
      "Bareza",
      "Basca",
      "Brocolis",
      "Calabresa",
      "Carbonara",
      "Catuperu",
      "Cheddar",
      "Cinco Queijos",
      "Frango",
      "Margarita",
      "Milho",
      "Mussarela",
      "Portuguesa",
      "Quatro Queijos",
      "Strogonoff",
      "Vegetariana"
    ]
    |> Enum.with_index()
    |> Enum.map(fn {label, position} -> %{label: label, position: position} end)
  end
end

Escalimetro.Repo.DevSeed.run()
