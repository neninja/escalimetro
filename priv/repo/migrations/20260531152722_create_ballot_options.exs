defmodule Escalimetro.Repo.Migrations.CreateBallotOptions do
  use Ecto.Migration

  def change do
    create table(:ballot_options) do
      add :ballot_id, references(:ballots, on_delete: :delete_all), null: false
      add :label, :string, null: false
      add :position, :integer, null: false, default: 0
      add :suggested_by_participant_id, :bigint
      add :rejected_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:ballot_options, [:ballot_id])
    create index(:ballot_options, [:ballot_id, :position])
    create index(:ballot_options, [:suggested_by_participant_id])
    create unique_index(:ballot_options, [:ballot_id, :label])
  end
end
