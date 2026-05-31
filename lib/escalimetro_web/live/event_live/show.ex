defmodule EscalimetroWeb.EventLive.Show do
  use EscalimetroWeb, :live_view

  alias Escalimetro.Events

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="mx-auto w-full max-w-7xl space-y-4"
    >
      <section id={"event-show-#{@event.id}"} class="mx-auto w-full max-w-4xl space-y-8">
        <header class="border-b border-base-content/10 pb-6">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div class="min-w-0">
              <.link
                navigate={~p"/events"}
                class="inline-flex items-center gap-2 text-sm font-semibold text-primary hover:underline"
              >
                <.icon name="hero-arrow-left" class="size-4" /> Eventos
              </.link>
              <div class="mt-4 flex flex-wrap items-center gap-3">
                <h1 class="text-3xl font-semibold leading-tight">{@event.title}</h1>
                <span class={[
                  "rounded-full px-2.5 py-1 text-xs font-semibold",
                  status_badge_class(@event.status)
                ]}>
                  {status_label(@event.status)}
                </span>
              </div>
              <p
                :if={@event.description}
                class="mt-3 max-w-3xl text-sm leading-6 text-base-content/70"
              >
                {@event.description}
              </p>
            </div>

            <div :if={@can_manage_event?} id="event-admin-actions" class="flex shrink-0 gap-2">
              <.button
                :if={@event.status != "completed"}
                navigate={~p"/events/#{@event}/edit"}
                class="btn btn-soft"
              >
                <.icon name="hero-pencil-square" class="size-4" /> Editar
              </.button>
              <button
                :if={@event.status != "completed"}
                id="event-complete-button"
                type="button"
                phx-click="complete"
                data-confirm="Concluir este evento? Pautas abertas serao fechadas."
                class="inline-flex items-center justify-center gap-2 rounded-md bg-base-content px-4 py-2 text-sm font-semibold text-base-100 shadow-sm transition hover:-translate-y-0.5 hover:bg-base-content/85"
              >
                <.icon name="hero-check-circle" class="size-4" /> Concluir
              </button>
            </div>
          </div>
        </header>

        <dl class="grid gap-4 sm:grid-cols-2">
          <div class="rounded-lg border border-base-content/10 bg-base-100 p-4">
            <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
              Data e hora
            </dt>
            <dd class="mt-2 text-sm font-medium">{scheduled_label(@event)}</dd>
          </div>
          <div class="rounded-lg border border-base-content/10 bg-base-100 p-4">
            <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/50">Local</dt>
            <dd class="mt-2 text-sm font-medium">{@event.location || "Sem local definido"}</dd>
          </div>
          <div class="rounded-lg border border-base-content/10 bg-base-100 p-4">
            <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
              Responsavel
            </dt>
            <dd class="mt-2 text-sm font-medium">{@event.owner_user.email}</dd>
          </div>
          <div class="rounded-lg border border-base-content/10 bg-base-100 p-4">
            <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
              Concluido em
            </dt>
            <dd class="mt-2 text-sm font-medium">{completed_label(@event)}</dd>
          </div>
        </dl>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case fetch_event(socket, id) do
      {:ok, event} ->
        {:ok, assign_event(socket, event)}

      :error ->
        {:ok, redirect_to_events(socket)}
    end
  end

  @impl true
  def handle_event("complete", _params, socket) do
    case Events.complete_event(socket.assigns.current_scope, socket.assigns.event) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evento concluido com sucesso.")
         |> assign_event(event)}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Este evento ja esta concluido.")}

      {:error, :unauthorized} ->
        {:noreply, redirect_to_events(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel concluir o evento.")}
    end
  end

  defp fetch_event(socket, id) do
    {:ok, Events.get_event!(socket.assigns.current_scope, id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  defp assign_event(socket, event) do
    assign(socket,
      event: event,
      can_manage_event?: Events.can_manage_event?(socket.assigns.current_scope, event)
    )
  end

  defp redirect_to_events(socket) do
    socket
    |> put_flash(:error, "Evento nao encontrado ou sem acesso.")
    |> push_navigate(to: ~p"/events")
  end

  defp scheduled_label(%{scheduled_at: nil}), do: "Sem data definida"

  defp scheduled_label(%{scheduled_at: scheduled_at}) do
    Calendar.strftime(scheduled_at, "%d/%m/%Y %H:%M")
  end

  defp completed_label(%{completed_at: nil}), do: "Nao concluido"

  defp completed_label(%{completed_at: completed_at}) do
    Calendar.strftime(completed_at, "%d/%m/%Y %H:%M")
  end

  defp status_label("draft"), do: "Rascunho"
  defp status_label("open"), do: "Aberto"
  defp status_label("completed"), do: "Concluido"

  defp status_badge_class("draft"), do: "bg-amber-100 text-amber-800"
  defp status_badge_class("open"), do: "bg-emerald-100 text-emerald-800"
  defp status_badge_class("completed"), do: "bg-slate-200 text-slate-700"
end
