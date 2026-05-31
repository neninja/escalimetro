defmodule Escalimetro.Repo.Migrations.CreateVotes do
  use Ecto.Migration

  def change do
    create table(:votes) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :ballot_id, references(:ballots, on_delete: :delete_all), null: false
      add :participant_id, references(:event_participants, on_delete: :delete_all), null: false
      add :ballot_option_id, references(:ballot_options, on_delete: :delete_all)
      add :value, :string
      add :justification, :text
      add :rejected_at, :utc_datetime
      add :rejected_by_user_id, references(:users, on_delete: :nilify_all)
      add :rejection_reason, :string

      timestamps(type: :utc_datetime)
    end

    create constraint(:votes, :votes_value_check,
             check: "value IS NULL OR value IN ('yes', 'no', 'maybe')"
           )

    create constraint(:votes, :votes_option_or_value_check,
             check: "ballot_option_id IS NOT NULL OR value IS NOT NULL"
           )

    create index(:votes, [:event_id])
    create index(:votes, [:ballot_id])
    create index(:votes, [:participant_id])
    create index(:votes, [:ballot_id, :ballot_option_id])
    create index(:votes, [:rejected_by_user_id])

    create unique_index(:votes, [:event_id, :ballot_id, :participant_id, :ballot_option_id],
             name: :votes_active_option_unique_index,
             where: "ballot_option_id IS NOT NULL AND rejected_at IS NULL"
           )

    create unique_index(:votes, [:event_id, :ballot_id, :participant_id],
             name: :votes_active_value_unique_index,
             where: "ballot_option_id IS NULL AND rejected_at IS NULL"
           )
  end
end
