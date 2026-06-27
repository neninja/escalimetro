defmodule Escalimetro.Events.Event do
  use Ecto.Schema

  import Ecto.Changeset

  alias Escalimetro.Accounts.User
  alias Escalimetro.Events.{Ballot, EventAdmin, EventParticipant, Vote}

  @statuses ~w(draft open completed)

  schema "events" do
    field :title, :string
    field :description, :string
    field :scheduled_at, :utc_datetime
    field :location, :string
    field :status, :string, default: "draft"
    field :completed_at, :utc_datetime
    field :public_invite_id, Ecto.UUID

    belongs_to :owner_user, User
    has_many :event_admins, EventAdmin
    has_many :admins, through: [:event_admins, :user]
    has_many :ballots, Ballot
    has_many :participants, EventParticipant
    has_many :votes, Vote

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(event, attrs) do
    attrs = normalize_datetime_local(attrs, :scheduled_at)

    event
    |> cast(attrs, [:title, :description, :scheduled_at, :location, :status, :completed_at])
    |> put_public_invite_id()
    |> validate_required([:title, :status, :owner_user_id])
    |> validate_length(:title, max: 160)
    |> validate_length(:description, max: 5_000)
    |> validate_length(:location, max: 160)
    |> validate_inclusion(:status, @statuses)
    |> validate_completed_at()
    |> foreign_key_constraint(:owner_user_id)
    |> unique_constraint(:public_invite_id)
    |> check_constraint(:status, name: :events_status_check)
  end

  def complete_changeset(event, completed_at) do
    event
    |> change(status: "completed", completed_at: completed_at)
    |> validate_required([:title, :status, :owner_user_id, :completed_at])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :events_status_check)
  end

  defp validate_completed_at(changeset) do
    if get_field(changeset, :status) == "completed" do
      validate_required(changeset, [:completed_at])
    else
      changeset
    end
  end

  defp put_public_invite_id(changeset) do
    case get_field(changeset, :public_invite_id) do
      nil -> put_change(changeset, :public_invite_id, Ecto.UUID.generate())
      _public_invite_id -> changeset
    end
  end

  defp normalize_datetime_local(%{} = attrs, field) do
    attrs
    |> normalize_datetime_local_key(field)
    |> normalize_datetime_local_key(Atom.to_string(field))
  end

  defp normalize_datetime_local(attrs, _field), do: attrs

  defp normalize_datetime_local_key(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        Map.put(attrs, key, normalize_datetime_local_value(value))

      _ ->
        attrs
    end
  end

  defp normalize_datetime_local_value(value) do
    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/, value) -> value <> ":00Z"
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/, value) -> value <> "Z"
      true -> value
    end
  end
end
