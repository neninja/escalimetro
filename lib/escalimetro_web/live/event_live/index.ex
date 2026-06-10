defmodule EscalimetroWeb.EventLive.Index do
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
      <section id="events-index" class="mx-auto w-full max-w-5xl space-y-8">
        <header class="flex flex-col gap-4 border-b border-base-content/10 pb-6 sm:flex-row sm:items-end sm:justify-between">
          <div class="space-y-2">
            <p class="text-sm font-medium uppercase tracking-wide text-primary">Gestao de eventos</p>
            <h1 class="text-3xl font-semibold leading-tight text-base-content">
              Eventos administrados
            </h1>
            <p class="max-w-2xl text-sm leading-6 text-base-content/70">
              Crie, acompanhe e conclua eventos com pautas e votacoes associadas.
            </p>
          </div>

          <.button navigate={~p"/events/new"} variant="primary" class="btn btn-primary">
            <.icon name="hero-plus" class="size-4" /> Novo evento
          </.button>
        </header>

        <div
          id="events-loading"
          class="hidden items-center gap-3 rounded-lg border border-base-content/10 px-4 py-3 text-sm text-base-content/70 phx-page-loading:flex"
        >
          <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" /> Carregando eventos
        </div>

        <div
          :if={@total_events == 0}
          id="events-empty"
          class="rounded-lg border border-dashed border-base-content/20 bg-base-200/40 p-8 text-center"
        >
          <div class="mx-auto flex size-12 items-center justify-center rounded-full bg-primary/10 text-primary">
            <.icon name="hero-calendar-days" class="size-6" />
          </div>
          <h2 class="mt-4 text-lg font-semibold">Nenhum evento ainda</h2>
          <p class="mx-auto mt-2 max-w-md text-sm text-base-content/70">
            Comece criando um evento para organizar pautas, participantes e votacoes.
          </p>
          <.button navigate={~p"/events/new"} variant="primary" class="btn btn-primary mt-5">
            Criar primeiro evento
          </.button>
        </div>

        <div :if={@total_events > 0} class="grid gap-6 lg:grid-cols-3">
          <section class="space-y-3">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                Rascunhos
              </h2>
              <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs font-semibold">
                {@draft_count}
              </span>
            </div>
            <div id="draft-events" phx-update="stream" class="space-y-3">
              <p
                id="draft-events-empty"
                class="hidden only:block rounded-lg border border-dashed border-base-content/15 p-4 text-sm text-base-content/55"
              >
                Sem rascunhos.
              </p>
              <.event_card :for={{id, event} <- @streams.draft_events} id={id} event={event} />
            </div>
          </section>

          <section class="space-y-3">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                Abertos
              </h2>
              <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs font-semibold">
                {@open_count}
              </span>
            </div>
            <div id="open-events" phx-update="stream" class="space-y-3">
              <p
                id="open-events-empty"
                class="hidden only:block rounded-lg border border-dashed border-base-content/15 p-4 text-sm text-base-content/55"
              >
                Sem eventos abertos.
              </p>
              <.event_card :for={{id, event} <- @streams.open_events} id={id} event={event} />
            </div>
          </section>

          <section class="space-y-3">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                Concluidos
              </h2>
              <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs font-semibold">
                {@completed_count}
              </span>
            </div>
            <div id="completed-events" phx-update="stream" class="space-y-3">
              <p
                id="completed-events-empty"
                class="hidden only:block rounded-lg border border-dashed border-base-content/15 p-4 text-sm text-base-content/55"
              >
                Sem eventos concluidos.
              </p>
              <.event_card :for={{id, event} <- @streams.completed_events} id={id} event={event} />
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :event, Escalimetro.Events.Event, required: true

  defp event_card(assigns) do
    ~H"""
    <article
      id={@id}
      class="group rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm transition hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-md"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <.link
            navigate={~p"/events/#{@event}"}
            class="block truncate text-base font-semibold text-base-content group-hover:text-primary"
          >
            {@event.title}
          </.link>
          <p :if={@event.location} class="mt-1 flex items-center gap-1.5 text-xs text-base-content/60">
            <.icon name="hero-map-pin" class="size-3.5" /> {@event.location}
          </p>
        </div>
        <span class={[
          "shrink-0 rounded-full px-2 py-1 text-xs font-semibold",
          status_badge_class(@event.status)
        ]}>
          {status_label(@event.status)}
        </span>
      </div>

      <p :if={@event.description} class="mt-3 line-clamp-3 text-sm leading-6 text-base-content/70">
        {@event.description}
      </p>

      <div class="mt-4 flex items-center justify-between border-t border-base-content/10 pt-3 text-xs text-base-content/60">
        <span>{scheduled_label(@event)}</span>
        <div class="flex items-center gap-3">
          <.link navigate={~p"/events/#{@event}"} class="font-semibold text-primary hover:underline">
            Ver
          </.link>
          <.link
            :if={@event.status != "completed"}
            navigate={~p"/events/#{@event}/edit"}
            class="font-semibold text-primary hover:underline"
          >
            Editar
          </.link>
        </div>
      </div>
    </article>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    events = Events.list_events(socket.assigns.current_scope)

    {:ok, assign_event_groups(socket, events)}
  end

  defp assign_event_groups(socket, events) do
    drafts = Enum.filter(events, &(&1.status == "draft"))
    open = Enum.filter(events, &(&1.status == "open"))
    completed = Enum.filter(events, &(&1.status == "completed"))

    socket
    |> assign(:total_events, length(events))
    |> assign(:draft_count, length(drafts))
    |> assign(:open_count, length(open))
    |> assign(:completed_count, length(completed))
    |> stream(:draft_events, drafts, reset: true)
    |> stream(:open_events, open, reset: true)
    |> stream(:completed_events, completed, reset: true)
  end

  defp scheduled_label(%{scheduled_at: nil}), do: "Sem data"

  defp scheduled_label(%{scheduled_at: scheduled_at}) do
    Calendar.strftime(scheduled_at, "%d/%m/%Y %H:%M")
  end

  defp status_label("draft"), do: "Rascunho"
  defp status_label("open"), do: "Aberto"
  defp status_label("completed"), do: "Concluido"

  defp status_badge_class("draft"), do: "bg-amber-100 text-amber-800"
  defp status_badge_class("open"), do: "bg-emerald-100 text-emerald-800"
  defp status_badge_class("completed"), do: "bg-slate-200 text-slate-700"
end
