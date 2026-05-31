defmodule Escalimetro.Repo.Migrations.CreateEventInvites do
  use Ecto.Migration

  def change do
    create table(:event_invites) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :token_hash, :string, null: false
      add :status, :string, null: false, default: "active"
      add :created_by_user_id, references(:users), null: false
      add :invalidated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create constraint(:event_invites, :event_invites_status_check,
             check: "status IN ('active', 'invalidated')"
           )

    create constraint(:event_invites, :event_invites_invalidated_at_check,
             check:
               "(status = 'active' AND invalidated_at IS NULL) OR (status = 'invalidated' AND invalidated_at IS NOT NULL)"
           )

    create index(:event_invites, [:event_id])
    create index(:event_invites, [:created_by_user_id])
    create unique_index(:event_invites, [:token_hash])

    create unique_index(:event_invites, [:event_id],
             name: :event_invites_active_event_unique_index,
             where: "status = 'active'"
           )
  end
end
