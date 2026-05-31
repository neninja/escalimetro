defmodule Escalimetro.Repo.Migrations.CreateBallots do
  use Ecto.Migration

  def change do
    create table(:ballots) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :kind, :string, null: false, default: "multiple_choice"
      add :allow_sugestion, :boolean, null: false, default: false
      add :status, :string, null: false, default: "open"
      add :position, :integer, null: false, default: 0
      add :closed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create constraint(:ballots, :ballots_kind_check,
             check: "kind IN ('multiple_choice', 'yes_no_maybe')"
           )

    create constraint(:ballots, :ballots_status_check, check: "status IN ('open', 'closed')")

    create index(:ballots, [:event_id])
    create index(:ballots, [:event_id, :status])
    create index(:ballots, [:event_id, :position])
  end
end
