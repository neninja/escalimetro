defmodule Escalimetro.Repo.Migrations.AddBallotVoteConfiguration do
  use Ecto.Migration

  def up do
    alter table(:ballots) do
      add :selection_mode, :string, null: false, default: "single_choice"
      add :show_justifications, :boolean, null: false, default: false
    end

    create constraint(:ballots, :ballots_selection_mode_check,
             check: "selection_mode IN ('single_choice', 'multi_choice')"
           )

    alter table(:votes) do
      add :selection_mode, :string, null: false, default: "single_choice"
    end

    create constraint(:votes, :votes_selection_mode_check,
             check: "selection_mode IN ('single_choice', 'multi_choice')"
           )

    drop constraint(:votes, :votes_option_or_value_check)

    create constraint(:votes, :votes_option_or_value_check,
             check: "(ballot_option_id IS NULL) <> (value IS NULL)"
           )

    create unique_index(:votes, [:event_id, :ballot_id, :participant_id, :selection_mode],
             name: :votes_active_single_choice_unique_index,
             where:
               "ballot_option_id IS NOT NULL AND rejected_at IS NULL AND selection_mode = 'single_choice'"
           )
  end

  def down do
    drop_if_exists index(:votes, [:event_id, :ballot_id, :participant_id, :selection_mode],
                     name: :votes_active_single_choice_unique_index
                   )

    drop constraint(:votes, :votes_option_or_value_check)

    create constraint(:votes, :votes_option_or_value_check,
             check: "ballot_option_id IS NOT NULL OR value IS NOT NULL"
           )

    drop constraint(:votes, :votes_selection_mode_check)

    alter table(:votes) do
      remove :selection_mode
    end

    drop constraint(:ballots, :ballots_selection_mode_check)

    alter table(:ballots) do
      remove :selection_mode
      remove :show_justifications
    end
  end
end
