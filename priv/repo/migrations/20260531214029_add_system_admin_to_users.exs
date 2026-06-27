defmodule Escalimetro.Repo.Migrations.AddSystemAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :system_admin, :boolean, null: false, default: false
    end
  end
end
