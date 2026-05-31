defmodule EscalimetroWeb.BackofficeLive.Dashboard do
  use EscalimetroWeb, :live_view

  alias Escalimetro.Backoffice

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="mx-auto w-full max-w-7xl space-y-4"
    >
      <section id="backoffice-dashboard" class="mx-auto w-full max-w-6xl space-y-8">
        <header class="flex flex-col gap-4 border-b border-base-content/10 pb-6 sm:flex-row sm:items-end sm:justify-between">
          <div class="space-y-2">
            <p class="text-sm font-medium uppercase tracking-wide text-primary">Backoffice</p>
            <h1 class="text-3xl font-semibold leading-tight text-base-content">
              Operacao do sistema
            </h1>
            <p class="max-w-2xl text-sm leading-6 text-base-content/70">
              Acompanhe uso geral e acesse a visao de usuarios para verificacao de suporte.
            </p>
          </div>
          <.link
            navigate={~p"/events"}
            class="inline-flex items-center justify-center gap-2 rounded-md border border-base-content/15 px-4 py-2 text-sm font-semibold transition hover:-translate-y-0.5 hover:border-primary/30 hover:text-primary"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Eventos
          </.link>
        </header>

        <section id="backoffice-stats" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <.stat_card
            id="backoffice-active-users-count"
            icon="hero-user-circle"
            label="Usuarios ativos"
            value={@stats.active_users_count}
            hint={"#{@stats.total_users_count} usuario(s) no total"}
          />
          <.stat_card
            id="backoffice-open-events-count"
            icon="hero-calendar-days"
            label="Eventos abertos"
            value={@stats.open_events_count}
            hint={"#{@stats.draft_events_count} rascunho(s), #{@stats.completed_events_count} concluido(s)"}
          />
          <.stat_card
            id="backoffice-open-ballots-count"
            icon="hero-list-bullet"
            label="Pautas abertas"
            value={@stats.open_ballots_count}
            hint={"#{@stats.closed_ballots_count} pauta(s) fechada(s)"}
          />
          <.stat_card
            id="backoffice-active-votes-count"
            icon="hero-check-badge"
            label="Votos ativos"
            value={@stats.active_votes_count}
            hint={"#{@stats.rejected_votes_count} voto(s) rejeitado(s)"}
          />
        </section>

        <section class="space-y-4">
          <div class="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h2 class="text-xl font-semibold">Usuarios</h2>
              <p class="mt-1 text-sm text-base-content/65">
                Impersone contas para reproduzir cenarios sem alterar permissao do usuario.
              </p>
            </div>
            <span class="rounded-full bg-base-200 px-3 py-1 text-xs font-semibold text-base-content/70">
              {@stats.total_users_count} usuario(s)
            </span>
          </div>

          <div id="backoffice-users-list" phx-update="stream" class="space-y-3">
            <p
              id="backoffice-users-empty"
              class="hidden only:block rounded-lg border border-dashed border-base-content/15 p-6 text-center text-sm text-base-content/55"
            >
              Nenhum usuario encontrado.
            </p>
            <.user_row
              :for={{id, user} <- @streams.users}
              id={id}
              user={user}
              current_user={@current_scope.user}
              impersonation_form={@impersonation_form}
            />
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :hint, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <article id={@id} class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm">
      <div class="flex items-center justify-between gap-3">
        <p class="text-sm font-semibold text-base-content/60">{@label}</p>
        <span class="flex size-9 items-center justify-center rounded-md bg-primary/10 text-primary">
          <.icon name={@icon} class="size-5" />
        </span>
      </div>
      <p class="mt-4 text-3xl font-semibold tracking-normal text-base-content">{@value}</p>
      <p class="mt-1 text-xs text-base-content/55">{@hint}</p>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :user, Escalimetro.Accounts.User, required: true
  attr :current_user, Escalimetro.Accounts.User, required: true
  attr :impersonation_form, Phoenix.HTML.Form, required: true

  defp user_row(assigns) do
    ~H"""
    <article id={@id} class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="truncate font-semibold">{@user.email}</h3>
            <span
              :if={@user.system_admin}
              class="rounded-full bg-primary/10 px-2 py-1 text-xs font-semibold text-primary"
            >
              Backoffice
            </span>
            <span
              :if={not is_nil(@user.confirmed_at)}
              class="rounded-full bg-emerald-100 px-2 py-1 text-xs font-semibold text-emerald-800"
            >
              Ativo
            </span>
          </div>
          <p class="mt-1 text-sm text-base-content/60">
            Criado em {datetime_label(@user.inserted_at)}
          </p>
        </div>

        <.form
          for={@impersonation_form}
          id={"impersonate-user-form-#{@user.id}"}
          action={~p"/backoffice/users/#{@user}/impersonate"}
          method="post"
        >
          <button
            id={"impersonate-user-button-#{@user.id}"}
            type="submit"
            disabled={@user.id == @current_user.id}
            class="inline-flex items-center justify-center gap-2 rounded-md border border-base-content/15 px-3 py-2 text-sm font-semibold transition hover:-translate-y-0.5 hover:border-primary/30 hover:text-primary disabled:cursor-not-allowed disabled:opacity-40"
          >
            <.icon name="hero-eye" class="size-4" /> Impersonar
          </button>
        </.form>
      </div>
    </article>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    case Backoffice.dashboard_data(socket.assigns.current_scope) do
      {:ok, %{stats: stats, users: users}} ->
        {:ok,
         socket
         |> assign(:stats, stats)
         |> assign(:impersonation_form, to_form(%{}, as: :impersonation))
         |> stream(:users, users, reset: true)}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "Acesso restrito ao backoffice.")
         |> push_navigate(to: ~p"/events")}
    end
  end

  defp datetime_label(nil), do: "data indisponivel"

  defp datetime_label(datetime) do
    Calendar.strftime(datetime, "%d/%m/%Y %H:%M")
  end
end
