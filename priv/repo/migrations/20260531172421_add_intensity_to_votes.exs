defmodule Escalimetro.Repo.Migrations.AddIntensityToVotes do
  use Ecto.Migration

  def change do
    alter table(:votes) do
      add :intensity, :boolean, null: false, default: false
    end

    create constraint(:votes, :votes_intensity_requires_option_check,
             check: "ballot_option_id IS NOT NULL OR intensity = false"
           )
  end
end
