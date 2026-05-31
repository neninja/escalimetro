defmodule Escalimetro.Repo.Migrations.CreateEventAdmins do
  use Ecto.Migration

  def change do
    create table(:event_admins) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:event_admins, [:event_id])
    create index(:event_admins, [:user_id])
    create unique_index(:event_admins, [:event_id, :user_id])
  end
end
