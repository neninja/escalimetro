defmodule Escalimetro.Events.Ballot do
  use Ecto.Schema

  import Ecto.Changeset

  alias Escalimetro.Events.{BallotOption, Event, Vote}

  @kinds ~w(multiple_choice yes_no_maybe)
  @selection_modes ~w(single_choice multi_choice)
  @statuses ~w(open closed)

  schema "ballots" do
    field :title, :string
    field :description, :string
    field :kind, :string, default: "multiple_choice"
    field :selection_mode, :string, default: "single_choice"
    field :allow_suggestion, :boolean, default: false
    field :show_justifications, :boolean, default: false
    field :status, :string, default: "open"
    field :position, :integer, default: 0
    field :closed_at, :utc_datetime

    belongs_to :event, Event
    has_many :options, BallotOption
    has_many :votes, Vote

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def selection_modes, do: @selection_modes
  def statuses, do: @statuses

  def changeset(ballot, attrs) do
    ballot
    |> cast(attrs, [
      :title,
      :description,
      :kind,
      :selection_mode,
      :allow_suggestion,
      :show_justifications,
      :status,
      :position,
      :closed_at
    ])
    |> validate_required([
      :event_id,
      :title,
      :kind,
      :selection_mode,
      :allow_suggestion,
      :show_justifications,
      :status,
      :position
    ])
    |> validate_length(:title, max: 160)
    |> validate_length(:description, max: 5_000)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:selection_mode, @selection_modes)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_mode_for_kind()
    |> validate_closed_at()
    |> foreign_key_constraint(:event_id)
    |> check_constraint(:kind, name: :ballots_kind_check)
    |> check_constraint(:selection_mode, name: :ballots_selection_mode_check)
    |> check_constraint(:status, name: :ballots_status_check)
  end

  def close_changeset(ballot, closed_at) do
    ballot
    |> change(status: "closed", closed_at: closed_at)
    |> validate_required([:event_id, :title, :kind, :status, :position, :closed_at])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :ballots_status_check)
  end

  def reopen_changeset(ballot) do
    ballot
    |> change(status: "open", closed_at: nil)
    |> validate_required([:event_id, :title, :kind, :status, :position])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :ballots_status_check)
  end

  defp validate_closed_at(changeset) do
    if get_field(changeset, :status) == "closed" do
      validate_required(changeset, [:closed_at])
    else
      changeset
    end
  end

  defp validate_mode_for_kind(changeset) do
    if get_field(changeset, :kind) == "yes_no_maybe" and
         get_field(changeset, :selection_mode) != "single_choice" do
      add_error(changeset, :selection_mode, "must be single choice for this ballot type")
    else
      changeset
    end
  end
end
