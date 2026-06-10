defmodule Escalimetro.Backoffice do
  @moduledoc """
  System backoffice dashboards and support actions.
  """

  import Ecto.Query, warn: false

  alias Escalimetro.Accounts
  alias Escalimetro.Accounts.{Scope, User}
  alias Escalimetro.Events.{Ballot, Event, Vote}
  alias Escalimetro.Repo

  def authorize_system_admin(%Scope{user: %User{} = user}) do
    if Accounts.system_admin?(user), do: :ok, else: {:error, :unauthorized}
  end

  def authorize_system_admin(_scope), do: {:error, :unauthorized}

  def dashboard_data(%Scope{} = scope) do
    with :ok <- authorize_system_admin(scope) do
      {:ok, %{stats: dashboard_stats(), users: list_backoffice_users()}}
    end
  end

  def dashboard_data(_scope), do: {:error, :unauthorized}

  def get_user_for_impersonation(%Scope{} = scope, user_id) do
    with :ok <- authorize_system_admin(scope),
         {:ok, id} <- cast_id(user_id),
         %User{} = user <- Repo.get(User, id),
         :ok <- ensure_not_self_impersonation(scope, user) do
      {:ok, user}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def get_user_for_impersonation(_scope, _user_id), do: {:error, :unauthorized}

  defp dashboard_stats do
    event_counts = counts_by_status(Event)
    ballot_counts = counts_by_status(Ballot)

    %{
      total_users_count: Repo.aggregate(User, :count),
      active_users_count: Repo.aggregate(active_users_query(), :count),
      total_events_count: Repo.aggregate(Event, :count),
      draft_events_count: Map.get(event_counts, "draft", 0),
      open_events_count: Map.get(event_counts, "open", 0),
      completed_events_count: Map.get(event_counts, "completed", 0),
      open_ballots_count: Map.get(ballot_counts, "open", 0),
      closed_ballots_count: Map.get(ballot_counts, "closed", 0),
      active_votes_count: Repo.aggregate(active_votes_query(), :count),
      rejected_votes_count: Repo.aggregate(rejected_votes_query(), :count)
    }
  end

  defp list_backoffice_users do
    User
    |> order_by([user], desc: user.system_admin, desc: user.inserted_at)
    |> Repo.all()
  end

  defp active_users_query do
    from user in User,
      where: not is_nil(user.confirmed_at)
  end

  defp active_votes_query do
    from vote in Vote,
      where: is_nil(vote.rejected_at)
  end

  defp rejected_votes_query do
    from vote in Vote,
      where: not is_nil(vote.rejected_at)
  end

  defp counts_by_status(schema) do
    schema
    |> group_by([record], record.status)
    |> select([record], {record.status, count(record.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp ensure_not_self_impersonation(%Scope{user: %User{id: user_id}}, %User{id: user_id}) do
    {:error, :self_impersonation}
  end

  defp ensure_not_self_impersonation(%Scope{}, %User{}), do: :ok

  defp cast_id(id) when is_integer(id), do: {:ok, id}

  defp cast_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, :not_found}
    end
  end

  defp cast_id(_id), do: {:error, :not_found}
end
