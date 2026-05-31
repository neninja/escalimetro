defmodule Escalimetro.EventsFixtures do
  @moduledoc """
  Helpers for creating event-management records in tests.
  """

  alias Escalimetro.Events

  import Escalimetro.AccountsFixtures

  def unique_event_title, do: "Evento #{System.unique_integer([:positive])}"
  def unique_ballot_title, do: "Pauta #{System.unique_integer([:positive])}"
  def unique_option_label, do: "Opcao #{System.unique_integer([:positive])}"

  def valid_event_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      title: unique_event_title(),
      description: "Descricao do evento",
      location: "Sala principal",
      status: "draft"
    })
  end

  def event_fixture(scope \\ user_scope_fixture(), attrs \\ %{}) do
    {:ok, event} = Events.create_event(scope, valid_event_attributes(attrs))
    event
  end

  def valid_ballot_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      title: unique_ballot_title(),
      description: "Descricao da pauta",
      kind: "multiple_choice",
      allow_sugestion: false,
      status: "open",
      position: 0
    })
  end

  def ballot_fixture(scope, event, attrs \\ %{}) do
    {:ok, ballot} = Events.create_ballot(scope, event, valid_ballot_attributes(attrs))
    ballot
  end

  def valid_ballot_option_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      label: unique_option_label(),
      position: 0
    })
  end

  def ballot_option_fixture(scope, ballot, attrs \\ %{}) do
    {:ok, option} =
      Events.create_ballot_option(scope, ballot, valid_ballot_option_attributes(attrs))

    option
  end

  def valid_event_participant_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      display_name: "Participante #{System.unique_integer([:positive])}",
      kind: "guest",
      status: "active",
      metadata: %{}
    })
  end

  def event_participant_fixture(scope, event, attrs \\ %{}) do
    {:ok, participant} =
      Events.create_event_participant(scope, event, valid_event_participant_attributes(attrs))

    participant
  end

  def valid_vote_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      value: "yes",
      justification: "Concordo"
    })
  end

  def vote_fixture(scope, event, participant, ballot, attrs \\ %{}) do
    {:ok, vote} =
      Events.create_vote(scope, event, participant, ballot, valid_vote_attributes(attrs))

    vote
  end
end
