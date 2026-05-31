defmodule Escalimetro.EventsTest do
  use Escalimetro.DataCase, async: true

  alias Escalimetro.Events

  alias Escalimetro.Events.{
    Ballot,
    BallotOption,
    Event,
    EventAdmin,
    EventInvite,
    EventParticipant,
    Vote
  }

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

    test "multiple choice ballots require at least two options" do
      scope = user_scope_fixture()
      event = event_fixture(scope)

      assert {:error, changeset} =
               Events.create_ballot(scope, event, %{
                 title: "Escolha uma opcao",
                 kind: "multiple_choice",
                 options: [%{label: "Unica"}]
               })

      assert "must have at least two options" in errors_on(changeset).options
    end

    test "create_ballot/3 creates ordered multiple choice options" do
      scope = user_scope_fixture()
      event = event_fixture(scope)

      assert {:ok, ballot} =
               Events.create_ballot(scope, event, %{
                 title: "Escolha o horario",
                 kind: "multiple_choice",
                 allow_sugestion: true,
                 options: [
                   %{label: "Manha", position: 1},
                   %{label: "Noite", position: 0}
                 ]
               })

      assert ballot.allow_sugestion
      assert Enum.map(ballot.options, & &1.label) == ["Noite", "Manha"]
    end

    test "yes_no_maybe ballots do not require custom options" do
      scope = user_scope_fixture()
      event = event_fixture(scope)

      assert {:ok, ballot} =
               Events.create_ballot(scope, event, %{
                 title: "Devemos aprovar?",
                 kind: "yes_no_maybe",
                 allow_sugestion: true
               })

      assert ballot.kind == "yes_no_maybe"
      assert ballot.options == []
    end

    test "update_ballot/3 updates editable options" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event)
      [first_option, second_option] = ballot.options

      assert {:ok, ballot} =
               Events.update_ballot(scope, ballot, %{
                 title: "Horario atualizado",
                 options: %{
                   "0" => %{"id" => first_option.id, "label" => "Tarde"},
                   "1" => %{"id" => second_option.id, "label" => "Noite"},
                   "2" => %{"label" => "Manha"}
                 }
               })

      assert ballot.title == "Horario atualizado"
      assert Enum.map(ballot.options, & &1.label) == ["Tarde", "Noite", "Manha"]
    end

    test "close_ballot/2 and reopen_ballot/2 only affect one ballot" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event)
      other_ballot = ballot_fixture(scope, event)

      assert {:ok, %Ballot{status: "closed", closed_at: closed_at}} =
               Events.close_ballot(scope, ballot)

      assert closed_at
      assert Repo.get!(Ballot, other_ballot.id).status == "open"

      assert {:ok, %Ballot{status: "open", closed_at: nil}} =
               Events.reopen_ballot(scope, Repo.get!(Ballot, ballot.id))
    end

    test "reopen_ballot/2 is blocked for completed events" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event)

      assert {:ok, closed_ballot} = Events.close_ballot(scope, ballot)
      assert {:ok, _event} = Events.complete_event(scope, event)

      assert {:error, :completed_event} = Events.reopen_ballot(scope, closed_ballot)
    end

    test "closed ballot does not accept new votes" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)

      assert {:ok, closed_ballot} = Events.close_ballot(scope, ballot)

      assert {:error, :closed_ballot} =
               Events.create_vote(scope, event, participant, closed_ballot, %{value: "yes"})
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

    test "list_participants/2 returns vote counts and separates rejected votes" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)
      rejected_participant = event_participant_fixture(scope, event)

      assert {:ok, _vote} = Events.create_vote(scope, event, participant, ballot, %{value: "yes"})

      assert {:ok, vote} =
               Events.create_vote(scope, event, rejected_participant, ballot, %{value: "no"})

      assert {:ok, _vote} = Events.reject_vote(scope, vote, %{})

      participants = Events.list_participants(scope, event)

      assert %EventParticipant{accepted_votes_count: 1, rejected_votes_count: 0} =
               Enum.find(participants, &(&1.id == participant.id))

      assert %EventParticipant{accepted_votes_count: 0, rejected_votes_count: 1} =
               Enum.find(participants, &(&1.id == rejected_participant.id))
    end

    test "invalidate_participant/2 marks participant and rejects active votes" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)
      assert {:ok, vote} = Events.create_vote(scope, event, participant, ballot, %{value: "yes"})

      assert {:ok, %EventParticipant{status: "invalidated", invalidated_at: invalidated_at}} =
               Events.invalidate_participant(scope, participant)

      assert invalidated_at

      assert %Vote{
               rejected_at: rejected_at,
               rejected_by_user_id: rejected_by_user_id,
               rejection_reason: "Participante invalidado"
             } = Repo.get!(Vote, vote.id)

      assert rejected_at
      assert rejected_by_user_id == scope.user.id
    end
  end

  describe "invites" do
    test "rotate_event_invite/2 creates an active invite with a hashed token" do
      scope = user_scope_fixture()
      event = event_fixture(scope)

      assert {:ok, %EventInvite{token: token, status: "active"} = invite} =
               Events.rotate_event_invite(scope, event)

      assert is_binary(token)
      assert byte_size(invite.token_hash) == 64
      refute invite.token_hash == token
      assert Events.get_active_invite_by_token(token).id == invite.id
      assert Events.get_active_event_invite(scope, event).id == invite.id
      refute Events.get_active_invite_by_token("invalid-token")
    end

    test "rotate_event_invite/2 invalidates the previous active invite" do
      scope = user_scope_fixture()
      event = event_fixture(scope)

      assert {:ok, first_invite} = Events.rotate_event_invite(scope, event)
      assert {:ok, second_invite} = Events.rotate_event_invite(scope, event)

      assert first_invite.id != second_invite.id
      assert Events.get_active_invite_by_token(first_invite.token) == nil
      assert Events.get_active_invite_by_token(second_invite.token).id == second_invite.id

      assert %EventInvite{status: "invalidated", invalidated_at: invalidated_at} =
               Repo.get!(EventInvite, first_invite.id)

      assert invalidated_at
      assert Repo.aggregate(EventInvite, :count) == 2
    end

    test "invalidate_event_invite/2 invalidates the active invite" do
      scope = user_scope_fixture()
      event = event_fixture(scope)

      assert {:ok, invite} = Events.rotate_event_invite(scope, event)

      assert {:ok, %EventInvite{status: "invalidated"}} =
               Events.invalidate_event_invite(scope, event)

      assert Events.get_active_event_invite(scope, event) == nil
      assert Events.get_active_invite_by_token(invite.token) == nil

      assert {:error, :invalid_invite} =
               Events.enter_event_invite(nil, invite, %{display_name: "Visitante"})
    end

    test "enter_event_invite/3 creates and reuses guest participants" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      assert {:ok, invite} = Events.rotate_event_invite(scope, event)

      assert {:error, changeset} = Events.enter_event_invite(nil, invite, %{display_name: "A"})
      assert "should be at least 2 character(s)" in errors_on(changeset).display_name

      assert {:ok, %EventParticipant{kind: "guest", display_name: "Visitante"} = participant} =
               Events.enter_event_invite(nil, invite, %{display_name: "  Visitante  "})

      assert {:ok, %EventParticipant{id: participant_id}} =
               Events.enter_event_invite(nil, invite, %{display_name: "Visitante"})

      assert participant_id == participant.id
    end

    test "enter_event_invite/3 creates and reuses authenticated user participants" do
      owner_scope = user_scope_fixture()
      event = event_fixture(owner_scope)
      assert {:ok, invite} = Events.rotate_event_invite(owner_scope, event)

      user = user_fixture()
      scope = user_scope_fixture(user)

      assert {:ok, %EventParticipant{kind: "user", user_id: user_id} = participant} =
               Events.enter_event_invite(scope, invite)

      assert user_id == user.id

      assert {:ok, %EventParticipant{id: participant_id}} =
               Events.enter_event_invite(scope, invite)

      assert participant_id == participant.id
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

    test "value votes do not accept intensity" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)

      assert {:error, changeset} =
               Events.create_vote(scope, event, participant, ballot, %{
                 value: "yes",
                 intensity: true
               })

      assert "is invalid" in errors_on(changeset).intensity
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

    test "reject_vote/3 accepts optional reason and restore_vote/2 clears rejection" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)
      assert {:ok, vote} = Events.create_vote(scope, event, participant, ballot, %{value: "yes"})

      assert {:ok,
              %Vote{
                rejected_at: rejected_at,
                rejected_by_user_id: rejected_by_user_id,
                rejection_reason: nil
              } = rejected_vote} = Events.reject_vote(scope, vote, %{})

      assert rejected_at
      assert rejected_by_user_id == scope.user.id

      assert {:ok, %Vote{rejected_at: nil, rejected_by_user_id: nil, rejection_reason: nil}} =
               Events.restore_vote(scope, rejected_vote)
    end

    test "reject_vote/3 and restore_vote/2 are blocked for completed events" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)
      assert {:ok, vote} = Events.create_vote(scope, event, participant, ballot, %{value: "yes"})
      assert {:ok, _event} = Events.complete_event(scope, event)

      assert {:error, :completed_event} = Events.reject_vote(scope, vote, %{})
      assert {:error, :completed_event} = Events.restore_vote(scope, vote)
    end

    test "restore_vote/2 is blocked for invalidated participants" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)
      assert {:ok, vote} = Events.create_vote(scope, event, participant, ballot, %{value: "yes"})

      assert {:ok, rejected_vote} =
               Events.reject_vote(scope, vote, %{rejection_reason: "Duplicado"})

      assert {:ok, _participant} = Events.invalidate_participant(scope, participant)

      assert {:error, :invalidated_participant} = Events.restore_vote(scope, rejected_vote)
    end

    test "suggest_ballot_option/4 requires suggestions enabled" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{allow_sugestion: true})
      participant = event_participant_fixture(scope, event)

      assert {:ok, %BallotOption{suggested_by_participant_id: participant_id}} =
               Events.suggest_ballot_option(event, participant, ballot, %{label: "Sugestao"})

      assert participant_id == participant.id

      closed_ballot = ballot_fixture(scope, event, %{allow_sugestion: false})

      assert {:error, :suggestions_disabled} =
               Events.suggest_ballot_option(event, participant, closed_ballot, %{label: "Outra"})
    end
  end

  describe "participant voting" do
    test "get_participant_event!/1 loads event participant ballots options and votes" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event)
      participant = event_participant_fixture(scope, event)
      [option | _] = ballot.options
      assert {:ok, _vote} = Events.cast_vote(participant, ballot, %{ballot_option_id: option.id})

      data = Events.get_participant_event!(participant.participant_token)

      assert data.event.id == event.id
      assert data.participant.id == participant.id
      assert [%Ballot{options: [_ | _]}] = data.ballots
      assert Map.has_key?(data.votes_by_ballot, ballot.id)
    end

    test "cast_vote/3 creates and changes a multiple choice vote with justification and intensity" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event)
      participant = event_participant_fixture(scope, event)
      [first_option, second_option] = ballot.options

      assert {:ok,
              %Vote{
                ballot_option_id: first_option_id,
                intensity: true,
                justification: "Preferencia"
              }} =
               Events.cast_vote(participant, ballot, %{
                 ballot_option_id: first_option.id,
                 intensity: "true",
                 justification: "Preferencia"
               })

      assert first_option_id == first_option.id

      assert {:ok, %Vote{id: vote_id, ballot_option_id: second_option_id, intensity: false}} =
               Events.cast_vote(participant, ballot, %{
                 ballot_option_id: second_option.id,
                 intensity: "false"
               })

      assert second_option_id == second_option.id

      active_votes =
        Repo.all(
          from vote in Vote,
            where:
              vote.event_id == ^event.id and vote.ballot_id == ^ballot.id and
                vote.participant_id == ^participant.id and is_nil(vote.rejected_at)
        )

      assert [%Vote{id: ^vote_id}] = active_votes
    end

    test "cast_vote/3 creates and changes a yes_no_maybe vote" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{kind: "yes_no_maybe"})
      participant = event_participant_fixture(scope, event)

      assert {:ok, %Vote{value: "yes", intensity: false}} =
               Events.cast_vote(participant, ballot, %{value: "yes", intensity: "true"})

      assert {:ok, %Vote{value: "maybe", intensity: false}} =
               Events.cast_vote(participant, ballot, %{value: "maybe"})
    end

    test "cast_vote/3 blocks completed events closed ballots invalidated participants and invalid options" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event)
      participant = event_participant_fixture(scope, event)

      assert {:error, :invalid_ballot_option} =
               Events.cast_vote(participant, ballot, %{ballot_option_id: -1})

      assert {:ok, closed_ballot} = Events.close_ballot(scope, ballot)

      assert {:error, :closed_ballot} =
               Events.cast_vote(participant, closed_ballot, %{
                 ballot_option_id: hd(ballot.options).id
               })

      open_ballot = ballot_fixture(scope, event)
      assert {:ok, _participant} = Events.invalidate_participant(scope, participant)

      assert {:error, :invalidated_participant} =
               Events.cast_vote(participant, open_ballot, %{
                 ballot_option_id: hd(open_ballot.options).id
               })

      other_participant = event_participant_fixture(scope, event)
      assert {:ok, completed_event} = Events.complete_event(scope, event)
      completed_ballot = Repo.get!(Ballot, open_ballot.id)

      assert {:error, :completed_event} =
               Events.cast_vote(other_participant, completed_ballot, %{
                 ballot_option_id: hd(open_ballot.options).id
               })

      assert completed_event.status == "completed"
    end
  end

  describe "participant suggestions" do
    test "suggest_option/3 creates a normalized unique suggestion" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{allow_sugestion: true})
      participant = event_participant_fixture(scope, event)

      assert {:ok,
              %BallotOption{label: "Nova opcao", suggested_by_participant_id: participant_id}} =
               Events.suggest_option(participant, ballot, %{label: "  Nova opcao  "})

      assert participant_id == participant.id

      assert {:error, changeset} =
               Events.suggest_option(participant, ballot, %{label: "nova   opcao"})

      assert "has already been suggested" in errors_on(changeset).label
    end

    test "suggest_option/3 blocks disabled suggestions closed ballots and completed events" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{allow_sugestion: false})
      participant = event_participant_fixture(scope, event)

      assert {:error, :suggestions_disabled} =
               Events.suggest_option(participant, ballot, %{label: "Sugestao"})

      enabled_ballot = ballot_fixture(scope, event, %{allow_sugestion: true})
      assert {:ok, closed_ballot} = Events.close_ballot(scope, enabled_ballot)

      assert {:error, :closed_ballot} =
               Events.suggest_option(participant, closed_ballot, %{label: "Sugestao"})

      other_ballot = ballot_fixture(scope, event, %{allow_sugestion: true})
      assert {:ok, _event} = Events.complete_event(scope, event)

      assert {:error, :completed_event} =
               Events.suggest_option(participant, other_ballot, %{label: "Sugestao"})
    end
  end

  describe "event results" do
    test "get_event_results/2 highlights the winner using intensity as tiebreaker" do
      scope = user_scope_fixture()
      event = event_fixture(scope, %{title: "Noite de pizza", location: "Salao"})

      ballot =
        ballot_fixture(scope, event, %{
          title: "Sabor",
          options: [
            %{label: "Calabresa", position: 0},
            %{label: "Marguerita", position: 1}
          ]
        })

      [calabresa, marguerita] = ballot.options

      calabresa_voters =
        for _index <- 1..2 do
          event_participant_fixture(scope, event)
        end

      marguerita_voters =
        for _index <- 1..2 do
          event_participant_fixture(scope, event)
        end

      for participant <- calabresa_voters do
        assert {:ok, %Vote{}} =
                 Events.create_vote(scope, event, participant, ballot, %{
                   ballot_option_id: calabresa.id
                 })
      end

      [intense_voter, regular_voter] = marguerita_voters

      assert {:ok, %Vote{}} =
               Events.create_vote(scope, event, intense_voter, ballot, %{
                 ballot_option_id: marguerita.id,
                 intensity: true
               })

      assert {:ok, %Vote{}} =
               Events.create_vote(scope, event, regular_voter, ballot, %{
                 ballot_option_id: marguerita.id
               })

      report = Events.get_event_results(scope, event)
      [result] = report.ballot_results

      assert report.active_votes_count == 4
      assert report.rejected_votes_count == 0
      assert result.active_votes_count == 4
      assert result.winner.label == "Marguerita"
      assert result.winner.intensity_count == 1
      assert Enum.map(result.option_results, & &1.label) == ["Marguerita", "Calabresa"]
      assert report.summary =~ "- Sabor: Marguerita (2 voto(s), 1 intenso(s))"
    end

    test "get_event_results/2 excludes rejected votes and exposes rejection details" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{title: "Disponibilidade", kind: "yes_no_maybe"})
      rejected_participant = event_participant_fixture(scope, event, %{display_name: "Ana"})
      active_participant = event_participant_fixture(scope, event, %{display_name: "Bia"})

      assert {:ok, rejected_vote} =
               Events.create_vote(scope, event, rejected_participant, ballot, %{value: "yes"})

      assert {:ok, %Vote{}} =
               Events.create_vote(scope, event, active_participant, ballot, %{value: "no"})

      assert {:ok, %Vote{}} =
               Events.reject_vote(scope, rejected_vote, %{rejection_reason: "Fora do criterio"})

      report = Events.get_event_results(scope, event)
      [result] = report.ballot_results

      assert report.active_votes_count == 1
      assert report.rejected_votes_count == 1
      assert result.winner.label == "Nao"

      assert [
               %{
                 participant_name: "Ana",
                 value_label: "Sim",
                 reason: "Fora do criterio"
               }
             ] = result.rejected_vote_results

      assert report.summary =~ "1 voto(s) rejeitado(s)"
    end
  end

  describe "pubsub" do
    test "broadcasts vote suggestions and ballot changes" do
      scope = user_scope_fixture()
      event = event_fixture(scope)
      ballot = ballot_fixture(scope, event, %{allow_sugestion: true})
      participant = event_participant_fixture(scope, event)
      [option | _] = ballot.options

      assert :ok = Events.subscribe_event(event)

      assert {:ok, _vote} = Events.cast_vote(participant, ballot, %{ballot_option_id: option.id})
      assert_receive {:event_changed, :vote_cast, event_id}
      assert event_id == event.id

      assert {:ok, _option} =
               Events.suggest_option(participant, ballot, %{label: "Sugestao nova"})

      assert_receive {:event_changed, :option_suggested, ^event_id}

      assert {:ok, _ballot} = Events.close_ballot(scope, ballot)
      assert_receive {:event_changed, :ballot_closed, ^event_id}
    end
  end
end
