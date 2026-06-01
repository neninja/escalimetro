defmodule Escalimetro.Events.Event do
  use Ecto.Schema

  import Ecto.Changeset

  alias Escalimetro.Accounts.User
  alias Escalimetro.Events.{Ballot, EventAdmin, EventInvite, EventParticipant, Vote}

  @statuses ~w(open closed)

  schema "events" do
    field :title, :string
    field :description, :string
    field :scheduled_at, :utc_datetime
    field :location, :string
    field :status, :string, default: "open"
    field :closed_at, :utc_datetime

    belongs_to :owner_user, User
    has_many :event_admins, EventAdmin
    has_many :admins, through: [:event_admins, :user]
    has_many :ballots, Ballot
    has_many :event_invites, EventInvite
    has_many :participants, EventParticipant
    has_many :votes, Vote

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(event, attrs) do
    attrs = normalize_datetime_local(attrs, :scheduled_at)

    event
    |> cast(attrs, [:title, :description, :scheduled_at, :location, :status, :closed_at])
    |> validate_required([:title, :status, :owner_user_id])
    |> validate_length(:title, max: 160)
    |> validate_length(:description, max: 5_000)
    |> validate_length(:location, max: 160)
    |> validate_inclusion(:status, @statuses)
    |> validate_closed_at()
    |> foreign_key_constraint(:owner_user_id)
    |> check_constraint(:status, name: :events_status_check)
  end

  def close_changeset(event, closed_at) do
    event
    |> change(status: "closed", closed_at: closed_at)
    |> validate_required([:title, :status, :owner_user_id, :closed_at])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :events_status_check)
  end

  def reopen_changeset(event) do
    event
    |> change(status: "open", closed_at: nil)
    |> validate_required([:title, :status, :owner_user_id])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :events_status_check)
  end

  defp validate_closed_at(changeset) do
    if get_field(changeset, :status) == "closed" do
      validate_required(changeset, [:closed_at])
    else
      changeset
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
