defmodule Escalimetro.Repo.Migrations.MigrateEventsToOpenClosed do
  use Ecto.Migration

  def up do
    drop constraint(:events, :events_status_check)

    execute "UPDATE events SET status = 'open' WHERE status = 'draft'"
    execute "UPDATE events SET status = 'closed' WHERE status = 'completed'"

    rename table(:events), :completed_at, to: :closed_at

    alter table(:events) do
      modify :status, :string, null: false, default: "open"
    end

    create constraint(:events, :events_status_check, check: "status IN ('open', 'closed')")
  end

  def down do
    drop constraint(:events, :events_status_check)

    alter table(:events) do
      modify :status, :string, null: false, default: "draft"
    end

    rename table(:events), :closed_at, to: :completed_at

    execute "UPDATE events SET status = 'draft' WHERE status = 'open'"
    execute "UPDATE events SET status = 'completed' WHERE status = 'closed'"

    create constraint(:events, :events_status_check,
             check: "status IN ('draft', 'open', 'completed')"
           )
  end
end
