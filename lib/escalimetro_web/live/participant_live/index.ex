defmodule EscalimetroWeb.ParticipantLive.Index do
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
      <section class="mx-auto w-full max-w-5xl space-y-8">
        <header class="border-b border-base-content/10 pb-6">
          <.link
            navigate={~p"/events/#{@event}"}
            class="inline-flex items-center gap-2 text-sm font-semibold text-primary hover:underline"
          >
            <.icon name="hero-arrow-left" class="size-4" /> {@event.title}
          </.link>
          <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h1 class="text-3xl font-semibold leading-tight">Participantes</h1>
              <p class="mt-2 text-sm leading-6 text-base-content/70">
                Acompanhe votos por participante e invalide participacoes quando necessario.
              </p>
            </div>
            <.button navigate={~p"/events/#{@event}/moderation"} class="btn btn-soft">
              <.icon name="hero-shield-check" class="size-4" /> Moderacao
            </.button>
          </div>
        </header>

        <section class="space-y-4">
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">Ativos</h2>
            <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs font-semibold">
              {length(@active_participants)}
            </span>
          </div>

          <div id="participants-list" class="space-y-3">
            <p
              :if={@active_participants == []}
              class="rounded-lg border border-dashed border-base-content/15 p-4 text-sm text-base-content/55"
            >
              Nenhum participante ativo.
            </p>
            <.participant_row
              :for={participant <- @active_participants}
              participant={participant}
              event={@event}
              can_mutate?={@event.status != "completed"}
            />
          </div>
        </section>

        <section class="space-y-4">
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
              Invalidados
            </h2>
            <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs font-semibold">
              {length(@invalidated_participants)}
            </span>
          </div>

          <div id="invalidated-participants-list" class="space-y-3">
            <p
              :if={@invalidated_participants == []}
              class="rounded-lg border border-dashed border-base-content/15 p-4 text-sm text-base-content/55"
            >
              Nenhum participante invalidado.
            </p>
            <.participant_row
              :for={participant <- @invalidated_participants}
              participant={participant}
              event={@event}
              can_mutate?={false}
            />
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  attr :participant, Escalimetro.Events.EventParticipant, required: true
  attr :event, Escalimetro.Events.Event, required: true
  attr :can_mutate?, :boolean, required: true

  defp participant_row(assigns) do
    ~H"""
    <article
      id={"participant-#{@participant.id}"}
      class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="font-semibold">{participant_name(@participant)}</h3>
            <span class={[
              "rounded-full px-2 py-1 text-xs font-semibold",
              @participant.status == "active" && "bg-emerald-100 text-emerald-800",
              @participant.status == "invalidated" && "bg-slate-200 text-slate-700"
            ]}>
              {participant_status(@participant.status)}
            </span>
          </div>
          <p class="mt-1 text-sm text-base-content/60">
            {@participant.total_votes_count} voto(s), {@participant.accepted_votes_count} ativo(s), {@participant.rejected_votes_count} rejeitado(s)
          </p>
        </div>

        <button
          :if={@participant.status == "active" and @can_mutate?}
          id={"participant-invalidate-button-#{@participant.id}"}
          type="button"
          phx-click="invalidate"
          phx-value-id={@participant.id}
          data-confirm="Invalidar participante e rejeitar seus votos ativos?"
          class="inline-flex items-center justify-center gap-2 rounded-md border border-error/30 px-3 py-2 text-sm font-semibold text-error transition hover:-translate-y-0.5 hover:bg-error/10"
        >
          <.icon name="hero-no-symbol" class="size-4" /> Invalidar
        </button>
      </div>
    </article>
    """
  end

  @impl true
  def mount(%{"event_id" => event_id}, _session, socket) do
    case fetch_event(socket, event_id) do
      {:ok, event} ->
        if connected?(socket), do: Events.subscribe_event(event)
        {:ok, assign_participants(assign(socket, :event, event))}

      :error ->
        {:ok, redirect_to_events(socket)}
    end
  end

  @impl true
  def handle_event("invalidate", %{"id" => id}, socket) do
    participant = Enum.find(socket.assigns.active_participants, &(&1.id == parse_id(id)))

    case participant && Events.invalidate_participant(socket.assigns.current_scope, participant) do
      {:ok, _participant} ->
        {:noreply,
         socket
         |> put_flash(:info, "Participante invalidado com sucesso.")
         |> assign_participants()}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos concluidos nao aceitam conciliacao.")}

      _other ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel invalidar participante.")}
    end
  end

  @impl true
  def handle_info({:event_changed, _event_name, _event_id}, socket) do
    {:noreply, assign_participants(socket)}
  end

  defp assign_participants(socket) do
    participants = Events.list_participants(socket.assigns.current_scope, socket.assigns.event)

    assign(socket,
      active_participants: Enum.filter(participants, &(&1.status == "active")),
      invalidated_participants: Enum.filter(participants, &(&1.status == "invalidated"))
    )
  end

  defp fetch_event(socket, event_id) do
    {:ok, Events.get_event!(socket.assigns.current_scope, event_id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  defp redirect_to_events(socket) do
    socket
    |> put_flash(:error, "Evento nao encontrado ou sem acesso.")
    |> push_navigate(to: ~p"/events")
  end

  defp participant_name(%{kind: "user", user: %{email: email}}), do: email

  defp participant_name(%{display_name: display_name}) when is_binary(display_name),
    do: display_name

  defp participant_name(_participant), do: "Participante"

  defp participant_status("active"), do: "Ativo"
  defp participant_status("invalidated"), do: "Invalidado"

  defp parse_id(value) when is_integer(value), do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, _rest} -> id
      :error -> nil
    end
  end

  defp parse_id(_value), do: nil
end
