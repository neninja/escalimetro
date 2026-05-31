defmodule Escalimetro.Events.BallotOption do
  use Ecto.Schema

  import Ecto.Changeset

  alias Escalimetro.Events.{Ballot, EventParticipant, Vote}

  schema "ballot_options" do
    field :label, :string
    field :position, :integer, default: 0
    field :rejected_at, :utc_datetime

    belongs_to :ballot, Ballot
    belongs_to :suggested_by_participant, EventParticipant
    has_many :votes, Vote

    timestamps(type: :utc_datetime)
  end

  def changeset(ballot_option, attrs) do
    ballot_option
    |> cast(attrs, [:label, :position, :rejected_at])
    |> validate_required([:ballot_id, :label, :position])
    |> validate_length(:label, max: 160)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:ballot_id)
    |> foreign_key_constraint(:suggested_by_participant_id)
    |> unique_constraint([:ballot_id, :label])
  end

  def reject_changeset(ballot_option, rejected_at) do
    ballot_option
    |> change(rejected_at: rejected_at)
    |> validate_required([:ballot_id, :label, :position, :rejected_at])
  end
end
