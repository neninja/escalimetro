defmodule Escalimetro.Events.EventInvite do
  use Ecto.Schema

  import Ecto.Changeset

  alias Escalimetro.Accounts.User
  alias Escalimetro.Events.Event

  @statuses ~w(active invalidated)

  schema "event_invites" do
    field :token_hash, :string
    field :status, :string, default: "active"
    field :invalidated_at, :utc_datetime
    field :token, :string, virtual: true

    belongs_to :event, Event
    belongs_to :created_by_user, User

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(event_invite, attrs) do
    event_invite
    |> cast(attrs, [:token_hash, :status, :invalidated_at])
    |> validate_required([:event_id, :token_hash, :status, :created_by_user_id])
    |> validate_length(:token_hash, is: 64)
    |> validate_inclusion(:status, @statuses)
    |> validate_invalidated_at()
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:created_by_user_id)
    |> unique_constraint(:token_hash)
    |> unique_constraint(:event_id, name: :event_invites_active_event_unique_index)
    |> check_constraint(:status, name: :event_invites_status_check)
    |> check_constraint(:invalidated_at, name: :event_invites_invalidated_at_check)
  end

  def invalidate_changeset(event_invite, invalidated_at) do
    event_invite
    |> change(status: "invalidated", invalidated_at: invalidated_at, token: nil)
    |> validate_required([:event_id, :token_hash, :status, :created_by_user_id, :invalidated_at])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :event_invites_status_check)
    |> check_constraint(:invalidated_at, name: :event_invites_invalidated_at_check)
  end

  defp validate_invalidated_at(changeset) do
    if get_field(changeset, :status) == "invalidated" do
      validate_required(changeset, [:invalidated_at])
    else
      changeset
    end
  end
end
