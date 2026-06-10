defmodule Escalimetro.Events.Vote do
  use Ecto.Schema

  import Ecto.Changeset

  alias Escalimetro.Accounts.User
  alias Escalimetro.Events.{Ballot, BallotOption, Event, EventParticipant}

  @values ~w(yes no maybe)

  schema "votes" do
    field :value, :string
    field :intensity, :boolean, default: false
    field :justification, :string
    field :rejected_at, :utc_datetime
    field :rejection_reason, :string

    belongs_to :event, Event
    belongs_to :ballot, Ballot
    belongs_to :participant, EventParticipant
    belongs_to :ballot_option, BallotOption
    belongs_to :rejected_by_user, User

    timestamps(type: :utc_datetime)
  end

  def values, do: @values

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [
      :ballot_option_id,
      :value,
      :intensity,
      :justification,
      :rejected_at,
      :rejection_reason
    ])
    |> validate_required([:event_id, :ballot_id, :participant_id])
    |> validate_length(:justification, max: 2_000)
    |> validate_length(:rejection_reason, max: 500)
    |> validate_inclusion(:value, @values)
    |> validate_option_or_value()
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:ballot_id)
    |> foreign_key_constraint(:participant_id)
    |> foreign_key_constraint(:ballot_option_id)
    |> foreign_key_constraint(:rejected_by_user_id)
    |> unique_constraint(:ballot_option_id, name: :votes_active_option_unique_index)
    |> unique_constraint(:participant_id, name: :votes_active_value_unique_index)
    |> check_constraint(:value, name: :votes_value_check)
    |> check_constraint(:ballot_option_id, name: :votes_option_or_value_check)
    |> check_constraint(:intensity, name: :votes_intensity_requires_option_check)
  end

  def reject_changeset(vote, rejected_by_user_id, attrs) do
    vote
    |> cast(attrs, [:rejection_reason])
    |> put_change(:rejected_at, DateTime.utc_now(:second))
    |> put_change(:rejected_by_user_id, rejected_by_user_id)
    |> validate_required([:rejected_at, :rejected_by_user_id])
    |> validate_length(:rejection_reason, max: 500)
    |> foreign_key_constraint(:rejected_by_user_id)
  end

  def restore_changeset(vote) do
    vote
    |> change(rejected_at: nil, rejected_by_user_id: nil, rejection_reason: nil)
    |> unique_constraint(:ballot_option_id, name: :votes_active_option_unique_index)
    |> unique_constraint(:participant_id, name: :votes_active_value_unique_index)
  end

  defp validate_option_or_value(changeset) do
    if get_field(changeset, :ballot_option_id) || get_field(changeset, :value) do
      changeset
    else
      add_error(changeset, :ballot_option_id, "or value must be present")
    end
  end
end
