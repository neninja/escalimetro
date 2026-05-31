defmodule EscalimetroWeb.Backoffice.UserImpersonationController do
  use EscalimetroWeb, :controller

  alias Escalimetro.Backoffice
  alias EscalimetroWeb.UserAuth

  def create(conn, %{"id" => user_id}) do
    case Backoffice.get_user_for_impersonation(conn.assigns.current_scope, user_id) do
      {:ok, user} ->
        conn
        |> UserAuth.impersonate_user(user)
        |> put_flash(:info, "Impersonando #{user.email}.")
        |> redirect(to: ~p"/events")

      {:error, :self_impersonation} ->
        conn
        |> put_flash(:error, "Nao e possivel impersonar o proprio usuario.")
        |> redirect(to: ~p"/backoffice")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Usuario nao encontrado.")
        |> redirect(to: ~p"/backoffice")

      {:error, :unauthorized} ->
        conn
        |> put_flash(:error, "Acesso restrito ao backoffice.")
        |> redirect(to: ~p"/events")
    end
  end

  def delete(conn, _params) do
    if UserAuth.impersonating?(conn) do
      conn
      |> UserAuth.stop_impersonating_user()
      |> put_flash(:info, "Impersonacao encerrada.")
      |> redirect(to: ~p"/backoffice")
    else
      conn
      |> put_flash(:error, "Nenhuma impersonacao ativa.")
      |> redirect(to: ~p"/events")
    end
  end
end
