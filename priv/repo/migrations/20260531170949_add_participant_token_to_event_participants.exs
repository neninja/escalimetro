defmodule Escalimetro.Repo.Migrations.AddParticipantTokenToEventParticipants do
  use Ecto.Migration

  def up do
    alter table(:event_participants) do
      add :participant_token, :string
    end

    execute """
    UPDATE event_participants
    SET participant_token = md5(random()::text || clock_timestamp()::text || id::text)
    WHERE participant_token IS NULL
    """

    alter table(:event_participants) do
      modify :participant_token, :string, null: false
    end

    create unique_index(:event_participants, [:participant_token])
  end

  def down do
    drop index(:event_participants, [:participant_token])

    alter table(:event_participants) do
      remove :participant_token
    end
  end
end
