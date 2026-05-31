defmodule Escalimetro.Events.Ballot do
  use Ecto.Schema

  import Ecto.Changeset

  alias Escalimetro.Events.{BallotOption, Event, Vote}

  @kinds ~w(multiple_choice yes_no_maybe)
  @statuses ~w(open closed)

  schema "ballots" do
    field :title, :string
    field :description, :string
    field :kind, :string, default: "multiple_choice"
    field :allow_sugestion, :boolean, default: false
    field :status, :string, default: "open"
    field :position, :integer, default: 0
    field :closed_at, :utc_datetime

    belongs_to :event, Event
    has_many :options, BallotOption
    has_many :votes, Vote

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  def changeset(ballot, attrs) do
    ballot
    |> cast(attrs, [
      :title,
      :description,
      :kind,
      :allow_sugestion,
      :status,
      :position,
      :closed_at
    ])
    |> validate_required([:event_id, :title, :kind, :allow_sugestion, :status, :position])
    |> validate_length(:title, max: 160)
    |> validate_length(:description, max: 5_000)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_closed_at()
    |> foreign_key_constraint(:event_id)
    |> check_constraint(:kind, name: :ballots_kind_check)
    |> check_constraint(:status, name: :ballots_status_check)
  end

  def close_changeset(ballot, closed_at) do
    ballot
    |> change(status: "closed", closed_at: closed_at)
    |> validate_required([:event_id, :title, :kind, :status, :position, :closed_at])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :ballots_status_check)
  end

  def reopen_changeset(ballot) do
    ballot
    |> change(status: "open", closed_at: nil)
    |> validate_required([:event_id, :title, :kind, :status, :position])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :ballots_status_check)
  end

  defp validate_closed_at(changeset) do
    if get_field(changeset, :status) == "closed" do
      validate_required(changeset, [:closed_at])
    else
      changeset
    end
  end
end
