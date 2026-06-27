defmodule Escalimetro.Repo.Migrations.AddPublicInviteIdToEvents do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto", ""

    alter table(:events) do
      add :public_invite_id, :uuid
    end

    execute(
      "UPDATE events SET public_invite_id = gen_random_uuid() WHERE public_invite_id IS NULL",
      "UPDATE events SET public_invite_id = NULL"
    )

    alter table(:events) do
      modify :public_invite_id, :uuid, null: false
    end

    create unique_index(:events, [:public_invite_id])
  end
end
