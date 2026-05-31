defmodule Escalimetro.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :title, :string, null: false
      add :description, :text
      add :scheduled_at, :utc_datetime
      add :location, :string
      add :status, :string, null: false, default: "draft"
      add :completed_at, :utc_datetime
      add :owner_user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:events, :events_status_check,
             check: "status IN ('draft', 'open', 'completed')"
           )

    create index(:events, [:owner_user_id])
    create index(:events, [:status])
    create index(:events, [:owner_user_id, :status])
  end
end
