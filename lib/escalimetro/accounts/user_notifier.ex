defmodule Escalimetro.Accounts.UserNotifier do
  import Swoosh.Email

  alias Escalimetro.Mailer
  alias Escalimetro.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Escalimetro", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Instrucoes para alterar email", """

    ==============================

    Ola #{user.email},

    Altere seu email acessando o link abaixo:

    #{url}

    Se voce nao solicitou essa alteracao, ignore esta mensagem.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Instrucoes de acesso", """

    ==============================

    Ola #{user.email},

    Acesse sua conta pelo link abaixo:

    #{url}

    Se voce nao solicitou este email, ignore esta mensagem.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Instrucoes de confirmacao", """

    ==============================

    Ola #{user.email},

    Confirme sua conta acessando o link abaixo:

    #{url}

    Se voce nao criou uma conta, ignore esta mensagem.

    ==============================
    """)
  end
end
