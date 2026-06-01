# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Escalimetro.Repo.insert!(%Escalimetro.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

defmodule Escalimetro.Repo.Seeds do
  alias Escalimetro.Accounts
  alias Escalimetro.Accounts.User
  alias Escalimetro.Repo

  @admin_email "admin@escalimetro.dev"
  @password "devpassword123"

  def run do
    admin =
      ensure_user!(@admin_email,
        password: @password,
        system_admin: true
      )

    IO.puts("Sysadmin: #{admin.email} / #{@password}")
  end

  defp ensure_user!(email, opts) do
    password = Keyword.fetch!(opts, :password)
    system_admin = Keyword.get(opts, :system_admin, false)

    user =
      case Accounts.get_user_by_email(email) do
        %User{} = user ->
          user

        nil ->
          {:ok, user} = Accounts.register_user(%{email: email})
          user
      end

    user = confirm_user!(user)
    user = set_password!(user, password)

    user
    |> Ecto.Changeset.change(system_admin: system_admin)
    |> Repo.update!()
  end

  defp confirm_user!(%User{} = user) do
    user
    |> User.confirm_changeset()
    |> Repo.update!()
  end

  defp set_password!(%User{} = user, password) do
    {:ok, {user, _expired_tokens}} = Accounts.update_user_password(user, %{password: password})
    user
  end
end

Escalimetro.Repo.Seeds.run()
