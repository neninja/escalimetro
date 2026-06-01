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

  def dashboard_data(scope, filters \\ %{})

  def dashboard_data(%Scope{} = scope, filters) do
    with :ok <- authorize_system_admin(scope) do
      filters = normalize_filters(filters)

      {:ok,
       %{
         filters: filters,
         stats: dashboard_stats(filters),
         users: list_backoffice_users(filters),
         events: list_backoffice_events(filters)
       }}
    end
  end

  def dashboard_data(_scope, _filters), do: {:error, :unauthorized}

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

  defp dashboard_stats(filters) do
    event_counts = Event |> range_query(filters) |> counts_by_status()
    ballot_counts = Ballot |> range_query(filters) |> counts_by_status()

    %{
      total_users_count: User |> range_query(filters) |> Repo.aggregate(:count),
      active_users_count: filters |> active_users_query() |> Repo.aggregate(:count),
      total_events_count: Event |> range_query(filters) |> Repo.aggregate(:count),
      open_events_count: Map.get(event_counts, "open", 0),
      closed_events_count: Map.get(event_counts, "closed", 0),
      open_ballots_count: Map.get(ballot_counts, "open", 0),
      closed_ballots_count: Map.get(ballot_counts, "closed", 0),
      active_votes_count: filters |> active_votes_query() |> Repo.aggregate(:count),
      rejected_votes_count: filters |> rejected_votes_query() |> Repo.aggregate(:count)
    }
  end

  defp list_backoffice_users(filters) do
    User
    |> range_query(filters)
    |> user_search_query(filters.user_query)
    |> order_by([user], desc: user.system_admin, desc: user.inserted_at)
    |> limit(50)
    |> Repo.all()
  end

  defp list_backoffice_events(filters) do
    Event
    |> range_query(filters)
    |> event_search_query(filters.event_query)
    |> order_by([event], asc: event.status, desc: event.inserted_at)
    |> preload(:owner_user)
    |> limit(50)
    |> Repo.all()
  end

  defp active_users_query(filters) do
    User
    |> where([user], not is_nil(user.confirmed_at))
    |> range_query(filters)
  end

  defp active_votes_query(filters) do
    Vote
    |> where([vote], is_nil(vote.rejected_at))
    |> range_query(filters)
  end

  defp rejected_votes_query(filters) do
    Vote
    |> where([vote], not is_nil(vote.rejected_at))
    |> range_query(filters)
  end

  defp range_query(queryable, %{from: nil, to: nil}), do: queryable

  defp range_query(queryable, %{from: from, to: nil}) do
    from record in queryable,
      where: record.inserted_at >= ^from
  end

  defp range_query(queryable, %{from: nil, to: to}) do
    from record in queryable,
      where: record.inserted_at <= ^to
  end

  defp range_query(queryable, %{from: from, to: to}) do
    from record in queryable,
      where: record.inserted_at >= ^from and record.inserted_at <= ^to
  end

  defp user_search_query(queryable, ""), do: queryable

  defp user_search_query(queryable, query) do
    pattern = "%#{query}%"

    from user in queryable,
      where: ilike(user.email, ^pattern)
  end

  defp event_search_query(queryable, ""), do: queryable

  defp event_search_query(queryable, query) do
    pattern = "%#{query}%"

    from event in queryable,
      where: ilike(event.title, ^pattern) or ilike(event.location, ^pattern)
  end

  defp counts_by_status(queryable) do
    queryable
    |> group_by([record], record.status)
    |> select([record], {record.status, count(record.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp normalize_filters(filters) when is_map(filters) do
    date_from = filters |> fetch_filter(:date_from, "date_from") |> normalize_date(:start)
    date_to = filters |> fetch_filter(:date_to, "date_to") |> normalize_date(:end)

    %{
      date_from: filters |> fetch_filter(:date_from, "date_from") |> normalize_string(),
      date_to: filters |> fetch_filter(:date_to, "date_to") |> normalize_string(),
      user_query: filters |> fetch_filter(:user_query, "user_query") |> normalize_string(),
      event_query: filters |> fetch_filter(:event_query, "event_query") |> normalize_string(),
      from: date_from,
      to: date_to
    }
  end

  defp normalize_filters(_filters), do: normalize_filters(%{})

  defp fetch_filter(filters, atom_key, string_key) do
    Map.get(filters, atom_key) || Map.get(filters, string_key)
  end

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(_value), do: ""

  defp normalize_date(value, boundary) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date_to_datetime(date, boundary)
      {:error, _reason} -> nil
    end
  end

  defp normalize_date(_value, _boundary), do: nil

  defp date_to_datetime(date, :start), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp date_to_datetime(date, :end), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

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
