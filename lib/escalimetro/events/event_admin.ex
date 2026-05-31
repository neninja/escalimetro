defmodule Escalimetro.Events.EventAdmin do
  use Ecto.Schema

  import Ecto.Changeset

  alias Escalimetro.Accounts.User
  alias Escalimetro.Events.Event

  schema "event_admins" do
    belongs_to :event, Event
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(event_admin, attrs) do
    event_admin
    |> cast(attrs, [])
    |> validate_required([:event_id, :user_id])
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:event_id, :user_id])
  end
end
