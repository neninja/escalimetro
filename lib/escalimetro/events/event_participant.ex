defmodule Escalimetro.Events.EventParticipant do
  use Ecto.Schema

  import Ecto.Changeset

  alias Escalimetro.Accounts.User
  alias Escalimetro.Events.{BallotOption, Event, Vote}

  @kinds ~w(user guest)
  @statuses ~w(active invalidated)

  schema "event_participants" do
    field :display_name, :string
    field :kind, :string, default: "guest"
    field :status, :string, default: "active"
    field :invalidated_at, :utc_datetime
    field :metadata, :map, default: %{}
    field :accepted_votes_count, :integer, virtual: true, default: 0
    field :rejected_votes_count, :integer, virtual: true, default: 0
    field :total_votes_count, :integer, virtual: true, default: 0

    belongs_to :event, Event
    belongs_to :user, User
    has_many :suggested_options, BallotOption, foreign_key: :suggested_by_participant_id
    has_many :votes, Vote, foreign_key: :participant_id

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  def changeset(event_participant, attrs) do
    event_participant
    |> cast(attrs, [:display_name, :kind, :status, :invalidated_at, :metadata])
    |> validate_required([:event_id, :kind, :status])
    |> validate_length(:display_name, max: 160)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_identity()
    |> validate_invalidated_at()
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:event_id, :user_id])
    |> check_constraint(:kind, name: :event_participants_kind_check)
    |> check_constraint(:status, name: :event_participants_status_check)
    |> check_constraint(:display_name, name: :event_participants_guest_display_name_check)
  end

  def invalidate_changeset(event_participant, invalidated_at) do
    event_participant
    |> change(status: "invalidated", invalidated_at: invalidated_at)
    |> validate_required([:event_id, :kind, :status, :invalidated_at])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :event_participants_status_check)
  end

  defp validate_identity(changeset) do
    case get_field(changeset, :kind) do
      "guest" -> validate_required(changeset, [:display_name])
      "user" -> validate_required(changeset, [:user_id])
      _ -> changeset
    end
  end

  defp validate_invalidated_at(changeset) do
    if get_field(changeset, :status) == "invalidated" do
      validate_required(changeset, [:invalidated_at])
    else
      changeset
    end
  end
end
