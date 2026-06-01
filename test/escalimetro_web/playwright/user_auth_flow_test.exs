defmodule EscalimetroWeb.Playwright.UserAuthFlowTest do
  use PhoenixTest.Playwright.Case, async: false, browser_pool: false

  use EscalimetroWeb, :verified_routes

  import Escalimetro.AccountsFixtures
  import Swoosh.TestAssertions

  alias Escalimetro.Accounts
  alias Escalimetro.Accounts.UserToken
  alias Escalimetro.Repo

  setup :set_swoosh_global

  test "user registers and is sent back to login", %{conn: conn} do
    email = unique_user_email()

    conn
    |> visit(~p"/users/register")
    |> assert_has("#registration_form")
    |> within("#registration_form", fn conn ->
      conn
      |> fill_in("Email", with: email)
      |> click_button("Criar conta")
    end)
    |> assert_path(~p"/users/log-in")
    |> assert_has("#flash-info", text: "Enviamos um email para #{email}")

    assert_email_sent(subject: "Instrucoes de confirmacao")
  end

  test "registration validates invalid and duplicated email", %{conn: conn} do
    existing_user = user_fixture(%{email: "existing-user@example.com"})
    discard_sent_emails()

    conn
    |> visit(~p"/users/register")
    |> within("#registration_form", fn conn ->
      conn
      |> fill_in("Email", with: "with spaces")
      |> assert_has("p", text: "must have the @ sign and no spaces")
      |> fill_in("Email", with: existing_user.email)
      |> click_button("Criar conta")
    end)
    |> assert_has("p", text: "has already been taken")
  end

  test "user logs in with password and logs out", %{conn: conn} do
    user = user_fixture() |> set_password()

    conn
    |> log_in_with_password(user.email)
    |> visit(~p"/users/settings")
    |> assert_has("#email_form")
    |> click_link("Sair")
    |> assert_path(~p"/")
  end

  test "invalid password returns to login with an error", %{conn: conn} do
    user = user_fixture() |> set_password()

    conn
    |> submit_password_login(user.email, "incorrect password")
    |> assert_path(~p"/users/log-in")
    |> assert_has("#login_form_password")
    |> assert_has("#flash-error", text: "Email ou senha invalidos")
  end

  test "authenticated user updates email and confirms the change", %{conn: conn} do
    user = user_fixture() |> set_password()
    new_email = unique_user_email()
    discard_sent_emails()

    conn
    |> log_in_with_magic_link(user)
    |> visit(~p"/users/settings")
    |> within("#email_form", fn conn ->
      conn
      |> fill_in("Email", with: new_email)
      |> click_button("Alterar email")
    end)
    |> assert_has("#flash-info", text: "Enviamos um link para confirmar a alteracao")

    assert {:email, email} = assert_email_sent()
    assert email.subject == "Instrucoes para alterar email"
    token = extract_url_token!(email.text_body, "/users/settings/confirm-email/")

    conn
    |> visit(~p"/users/settings/confirm-email/#{token}")
    |> assert_path(~p"/users/settings")
    |> assert_has("#flash-info", text: "Email alterado com sucesso.")

    refute Accounts.get_user_by_email(user.email)
    assert Accounts.get_user_by_email(new_email)
  end

  test "authenticated user updates password and can use the new password", %{conn: conn} do
    user = user_fixture() |> set_password()
    new_password = "new valid password!"

    conn
    |> log_in_with_magic_link(user)
    |> visit(~p"/users/settings")
    |> within("#password_form", fn conn ->
      conn
      |> fill_in("Nova senha", with: new_password)
      |> fill_in("Confirmar nova senha", with: new_password)
      |> click_button("Salvar senha")
    end)
    |> assert_path(~p"/users/settings")
    |> assert_has("#flash-info", text: "Senha atualizada com sucesso.")

    assert Accounts.get_user_by_email_and_password(user.email, new_password)
  end

  test "settings requires an authenticated user", %{conn: conn} do
    conn
    |> visit(~p"/users/settings")
    |> assert_path(~p"/users/log-in")
    |> assert_has("#flash-error", text: "Voce precisa entrar para acessar esta pagina.")
  end

  test "user logs in from magic link", %{conn: conn} do
    user = user_fixture()
    {token, _hashed_token} = generate_user_magic_link_token(user)

    conn
    |> visit(~p"/users/log-in/#{token}")
    |> assert_has("#login_form")
    |> click_button("Entrar apenas desta vez")
    |> assert_path(~p"/events")
  end

  test "invalid magic link redirects to login", %{conn: conn} do
    conn
    |> visit(~p"/users/log-in/not-a-real-token")
    |> assert_path(~p"/users/log-in")
    |> assert_has("#flash-error", text: "O link de acesso e invalido ou expirou.")
  end

  test "registered user can request a magic link", %{conn: conn} do
    user = user_fixture()
    discard_sent_emails()

    conn
    |> visit(~p"/users/log-in")
    |> within("#login_form_magic", fn conn ->
      conn
      |> fill_in("Email", with: user.email)
      |> click_button("Entrar com email")
    end)
    |> assert_path(~p"/users/log-in")
    |> assert_has("#flash-info", text: "Se o email estiver cadastrado")

    assert UserToken
           |> Repo.get_by!(user_id: user.id)
           |> Map.fetch!(:context) == "login"

    assert_email_sent(subject: "Instrucoes de acesso")
  end

  defp log_in_with_password(conn, email, password \\ valid_user_password()) do
    conn
    |> submit_password_login(email, password)
    |> assert_path(~p"/events", timeout: 5_000)
  end

  defp log_in_with_magic_link(conn, user) do
    {token, _hashed_token} = generate_user_magic_link_token(user)

    conn
    |> visit(~p"/users/log-in/#{token}")
    |> assert_has("#login_form")
    |> click_button("Entrar apenas desta vez")
    |> assert_path(~p"/events")
  end

  defp submit_password_login(conn, email, password) do
    conn
    |> visit(~p"/users/log-in")
    |> assert_has("#login_form_password")
    |> within("#login_form_password", fn conn ->
      conn
      |> fill_in("Email", with: email)
      |> fill_in("Senha", with: password)
    end)
    |> evaluate(
      "HTMLFormElement.prototype.submit.call(document.querySelector('#login_form_password'))"
    )
  end

  defp discard_sent_emails do
    receive do
      {:email, _email} -> discard_sent_emails()
    after
      0 -> :ok
    end
  end

  defp extract_url_token!(body, path) do
    escaped_path = Regex.escape(path)
    [_, token] = Regex.run(~r/#{escaped_path}([^\s]+)/, body)
    token
  end
end
