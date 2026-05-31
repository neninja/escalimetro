defmodule Escalimetro.Repo.Migrations.CreateEventParticipants do
  use Ecto.Migration

  def change do
    create table(:event_participants) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :display_name, :string
      add :kind, :string, null: false, default: "guest"
      add :status, :string, null: false, default: "active"
      add :invalidated_at, :utc_datetime
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create constraint(:event_participants, :event_participants_kind_check,
             check: "kind IN ('user', 'guest')"
           )

    create constraint(:event_participants, :event_participants_status_check,
             check: "status IN ('active', 'invalidated')"
           )

    create constraint(:event_participants, :event_participants_guest_display_name_check,
             check:
               "kind = 'user' OR (display_name IS NOT NULL AND length(btrim(display_name)) > 0)"
           )

    create index(:event_participants, [:event_id])
    create index(:event_participants, [:event_id, :status])
    create index(:event_participants, [:user_id])

    create unique_index(:event_participants, [:event_id, :user_id], where: "user_id IS NOT NULL")

    execute(
      """
      ALTER TABLE ballot_options
      ADD CONSTRAINT ballot_options_suggested_by_participant_id_fkey
      FOREIGN KEY (suggested_by_participant_id)
      REFERENCES event_participants(id)
      ON DELETE SET NULL
      """,
      "ALTER TABLE ballot_options DROP CONSTRAINT ballot_options_suggested_by_participant_id_fkey"
    )
  end
end
