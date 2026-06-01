defmodule Escalimetro.Repo.Migrations.RenameAllowSugestionToAllowSuggestion do
  use Ecto.Migration

  def change do
    rename table(:ballots), :allow_sugestion, to: :allow_suggestion
  end
end
