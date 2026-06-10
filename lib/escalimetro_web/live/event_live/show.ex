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
                id="event-results-link"
                navigate={~p"/events/#{@event}/results"}
                class="btn btn-soft"
              >
                <.icon name="hero-chart-bar" class="size-4" /> Resultados
              </.button>
              <.button
                :if={@event.status != "closed"}
                navigate={~p"/events/#{@event}/edit"}
                class="btn btn-soft"
              >
                <.icon name="hero-pencil-square" class="size-4" /> Editar
              </.button>
              <button
                :if={@event.status != "closed"}
                id="event-close-button"
                type="button"
                phx-click="close"
                data-confirm="Fechar este evento? Pautas abertas serao fechadas."
                class="inline-flex items-center justify-center gap-2 rounded-md bg-base-content px-4 py-2 text-sm font-semibold text-base-100 shadow-sm transition hover:-translate-y-0.5 hover:bg-base-content/85"
              >
                <.icon name="hero-lock-closed" class="size-4" /> Fechar
              </button>
              <button
                :if={@event.status == "closed"}
                id="event-reopen-button"
                type="button"
                phx-click="reopen"
                data-confirm="Reabrir este evento e suas pautas?"
                class="inline-flex items-center justify-center gap-2 rounded-md border border-emerald-500/30 px-4 py-2 text-sm font-semibold text-emerald-700 shadow-sm transition hover:-translate-y-0.5 hover:bg-emerald-500/10"
              >
                <.icon name="hero-lock-open" class="size-4" /> Reabrir
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
              Fechado em
            </dt>
            <dd class="mt-2 text-sm font-medium">{closed_label(@event)}</dd>
          </div>
        </dl>

        <nav
          id="event-mode-tabs"
          class="grid rounded-lg border border-base-content/10 bg-base-200/50 p-1 sm:grid-cols-2"
          aria-label="Modos do evento"
        >
          <button
            id="event-editor-tab"
            type="button"
            phx-click="select_tab"
            phx-value-tab="editor"
            class={[
              "inline-flex items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-semibold transition",
              @active_tab == "editor" && "bg-base-100 text-primary shadow-sm",
              @active_tab != "editor" && "text-base-content/60 hover:text-base-content"
            ]}
          >
            <.icon name="hero-pencil-square" class="size-4" /> Editar
          </button>
          <button
            id="event-voting-tab"
            type="button"
            phx-click="select_tab"
            phx-value-tab="participant"
            disabled={@editor_dirty?}
            class={[
              "inline-flex items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-40",
              @active_tab == "participant" && "bg-base-100 text-primary shadow-sm",
              @active_tab != "participant" && "text-base-content/60 hover:text-base-content"
            ]}
          >
            <.icon name="hero-check-circle" class="size-4" /> Votar
          </button>
        </nav>

        <section :if={@active_tab == "editor"} id="event-editor-panel" class="space-y-4">
          <.form
            :if={@event.status != "closed"}
            for={@event_form}
            id="event-management-form"
            phx-change="validate_event"
            phx-submit="save_event"
            class="space-y-5 rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
          >
            <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <h2 class="text-xl font-semibold">Dados do evento</h2>
                <p class="mt-1 text-sm text-base-content/65">
                  Salve as alteracoes antes de alternar para a aba de votacao.
                </p>
              </div>
              <span
                :if={@editor_dirty?}
                id="event-management-dirty-indicator"
                class="inline-flex items-center gap-2 rounded-full bg-warning/10 px-3 py-1 text-xs font-semibold text-warning"
              >
                <.icon name="hero-exclamation-triangle" class="size-4" /> Alteracoes pendentes
              </span>
            </div>

            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@event_form[:title]}
                id="event-management-title-input"
                type="text"
                label="Nome"
                maxlength="160"
                required
              />
              <div class="rounded-md border border-base-content/10 bg-base-200/40 px-3 py-2">
                <p class="text-sm font-semibold">Status</p>
                <p class="mt-2 text-sm text-base-content/70">{status_label(@event.status)}</p>
              </div>
            </div>

            <.input
              field={@event_form[:description]}
              id="event-management-description-input"
              type="textarea"
              label="Descricao"
              rows="4"
              maxlength="5000"
            />

            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@event_form[:scheduled_at]}
                id="event-management-scheduled-at-input"
                type="datetime-local"
                label="Data e hora"
              />
              <.input
                field={@event_form[:location]}
                id="event-management-location-input"
                type="text"
                label="Local"
                maxlength="160"
              />
            </div>

            <div class="flex justify-end border-t border-base-content/10 pt-4">
              <.button
                id="event-management-save-button"
                variant="primary"
                phx-disable-with="Salvando..."
                class="btn btn-primary"
              >
                <.icon name="hero-check" class="size-4" /> Salvar
              </.button>
            </div>
          </.form>

          <div
            :if={@event.status == "closed"}
            id="event-management-closed-editor"
            class="rounded-lg border border-base-content/10 bg-base-100 p-4 text-sm text-base-content/65"
          >
            Eventos fechados nao podem receber alteracoes. Reabra o evento para editar.
          </div>

          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="text-xl font-semibold">Pautas</h2>
              <p class="mt-1 text-sm text-base-content/65">
                Ordene, edite e encerre pautas individualmente sem afetar as demais.
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              <.button
                :if={@event.status != "closed"}
                navigate={~p"/events/#{@event}/ballots/new"}
                variant="primary"
                class="btn btn-primary"
              >
                <.icon name="hero-plus" class="size-4" /> Nova pauta
              </.button>
              <.button navigate={~p"/events/#{@event}/participants"} class="btn btn-soft">
                <.icon name="hero-users" class="size-4" /> Participantes
              </.button>
              <.button navigate={~p"/events/#{@event}/moderation"} class="btn btn-soft">
                <.icon name="hero-shield-check" class="size-4" /> Moderacao
              </.button>
              <.button navigate={~p"/events/#{@event}/invite"} class="btn btn-soft">
                <.icon name="hero-qr-code" class="size-4" /> Convite
              </.button>
            </div>
          </div>

          <div id="ballots-list" phx-update="stream" class="space-y-3">
            <div
              id="ballots-list-empty"
              class="hidden only:block rounded-lg border border-dashed border-base-content/15 p-6 text-center text-sm text-base-content/55"
            >
              Nenhuma pauta criada.
            </div>

            <article
              :for={{id, ballot} <- @streams.ballots}
              id={id}
              class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
            >
              <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                <div class="min-w-0 space-y-2">
                  <div class="flex flex-wrap items-center gap-2">
                    <h3 class="font-semibold">{ballot.title}</h3>
                    <span class={[
                      "rounded-full px-2 py-1 text-xs font-semibold",
                      ballot.status == "open" && "bg-emerald-100 text-emerald-800",
                      ballot.status == "closed" && "bg-slate-200 text-slate-700"
                    ]}>
                      {ballot_status_label(ballot.status)}
                    </span>
                    <span class="rounded-full bg-base-200 px-2 py-1 text-xs font-semibold">
                      {ballot_kind_label(ballot.kind)}
                    </span>
                  </div>
                  <p :if={ballot.description} class="text-sm leading-6 text-base-content/65">
                    {ballot.description}
                  </p>
                  <p class="text-sm text-base-content/55">
                    Posicao {ballot.position} · {option_summary(ballot)}
                    <span :if={ballot.kind == "multiple_choice"}>
                      · {selection_mode_label(ballot.selection_mode)}
                    </span>
                    <span :if={ballot.allow_suggestion}> · sugestoes habilitadas</span>
                    <span :if={ballot.show_justifications}> · justificativas visiveis</span>
                  </p>
                </div>

                <div class="flex shrink-0 flex-wrap gap-2">
                  <.button
                    :if={@event.status != "closed"}
                    navigate={~p"/events/#{@event}/ballots/#{ballot}/edit"}
                    class="btn btn-soft"
                  >
                    <.icon name="hero-pencil-square" class="size-4" /> Editar
                  </.button>
                  <button
                    :if={@event.status != "closed" and ballot.status == "open"}
                    id={"ballot-close-button-#{ballot.id}"}
                    type="button"
                    phx-click="close_ballot"
                    phx-value-id={ballot.id}
                    class="inline-flex items-center justify-center gap-2 rounded-md border border-base-content/15 px-3 py-2 text-sm font-semibold transition hover:-translate-y-0.5 hover:border-primary/30 hover:text-primary"
                  >
                    <.icon name="hero-lock-closed" class="size-4" /> Fechar
                  </button>
                  <button
                    :if={@event.status != "closed" and ballot.status == "closed"}
                    id={"ballot-reopen-button-#{ballot.id}"}
                    type="button"
                    phx-click="reopen_ballot"
                    phx-value-id={ballot.id}
                    class="inline-flex items-center justify-center gap-2 rounded-md border border-emerald-500/30 px-3 py-2 text-sm font-semibold text-emerald-700 transition hover:-translate-y-0.5 hover:bg-emerald-500/10"
                  >
                    <.icon name="hero-lock-open" class="size-4" /> Reabrir
                  </button>
                </div>
              </div>
            </article>
          </div>
        </section>

        <section :if={@active_tab == "participant"} id="event-participant-panel" class="space-y-4">
          <div>
            <h2 class="text-xl font-semibold">Votacao</h2>
            <p class="mt-1 text-sm text-base-content/65">
              Visualize as opcoes, votos parciais, favoritos e justificativas abertas por sanfona.
            </p>
          </div>

          <div id="participant-ballots-preview" phx-update="stream" class="space-y-3">
            <div
              id="participant-ballots-preview-empty"
              class="hidden only:block rounded-lg border border-dashed border-base-content/15 p-6 text-center text-sm text-base-content/55"
            >
              Nenhuma pauta disponivel.
            </div>

            <article
              :for={{id, ballot} <- @streams.participant_ballots}
              id={id}
              class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
            >
              <% result = Map.get(@results_by_ballot, ballot.id) %>

              <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <div class="flex flex-wrap items-center gap-2">
                    <h3 class="font-semibold">{ballot.title}</h3>
                    <span class="rounded-full bg-base-200 px-2 py-1 text-xs font-semibold">
                      {ballot_status_label(ballot.status)}
                    </span>
                    <span
                      :if={ballot.kind == "multiple_choice"}
                      class="rounded-full bg-base-200 px-2 py-1 text-xs font-semibold"
                    >
                      {selection_mode_label(ballot.selection_mode)}
                    </span>
                  </div>
                  <p :if={ballot.description} class="mt-2 text-sm leading-6 text-base-content/65">
                    {ballot.description}
                  </p>
                </div>
                <span
                  :if={result}
                  class="rounded-full bg-primary/10 px-3 py-1 text-sm font-semibold text-primary"
                >
                  {result.active_votes_count} voto(s)
                </span>
              </div>

              <div
                :if={result}
                id={"event-management-voting-results-#{ballot.id}"}
                class="mt-4 space-y-2"
              >
                <details
                  :for={option <- result.option_results}
                  id={"event-management-result-option-#{ballot.id}-#{option.key}"}
                  class="rounded-lg border border-base-content/10 bg-base-200/35 p-3 open:bg-base-200/60"
                >
                  <summary class="flex cursor-pointer list-none items-center justify-between gap-3 text-sm font-semibold">
                    <span class="min-w-0">
                      <span class="truncate">{option.label}</span>
                    </span>
                    <span class="flex shrink-0 flex-wrap justify-end gap-2 text-xs">
                      <span class="rounded-full bg-base-100 px-2 py-1">
                        {option.votes_count} voto(s)
                      </span>
                      <span
                        :if={ballot.kind == "multiple_choice"}
                        class="rounded-full bg-base-100 px-2 py-1"
                      >
                        {option.intensity_count} quero muito
                      </span>
                    </span>
                  </summary>
                  <div class="mt-3 space-y-2">
                    <p :if={option.voter_results == []} class="text-sm text-base-content/55">
                      Nenhum voto ativo nesta opcao.
                    </p>
                    <div
                      :for={vote <- option.voter_results}
                      id={"event-management-result-vote-#{vote.id}"}
                      class="rounded-md bg-base-100 px-3 py-2 text-sm"
                    >
                      <div class="flex flex-wrap items-center gap-2">
                        <span class="font-semibold">{vote.participant_name}</span>
                        <span
                          :if={vote.intensity}
                          class="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary"
                        >
                          Quero muito
                        </span>
                      </div>
                      <p
                        :if={ballot.show_justifications and vote.justification}
                        class="mt-1 text-base-content/65"
                      >
                        {vote.justification}
                      </p>
                    </div>
                  </div>
                </details>
              </div>
            </article>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case fetch_event(socket, id) do
      {:ok, event} ->
        if connected?(socket), do: Events.subscribe_event(event)
        {:ok, assign_event(socket, event)}

      :error ->
        {:ok, redirect_to_events(socket)}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    case Events.close_event(socket.assigns.current_scope, socket.assigns.event) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evento fechado com sucesso.")
         |> assign_event(event)}

      {:error, :closed_event} ->
        {:noreply, put_flash(socket, :error, "Este evento ja esta fechado.")}

      {:error, :unauthorized} ->
        {:noreply, redirect_to_events(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel fechar o evento.")}
    end
  end

  def handle_event("reopen", _params, socket) do
    case Events.reopen_event(socket.assigns.current_scope, socket.assigns.event) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evento reaberto com sucesso.")
         |> assign_event(event)}

      {:error, :open_event} ->
        {:noreply, put_flash(socket, :error, "Este evento ja esta aberto.")}

      {:error, :unauthorized} ->
        {:noreply, redirect_to_events(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel reabrir o evento.")}
    end
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) when tab in ["editor", "participant"] do
    if tab == "participant" and socket.assigns.editor_dirty? do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Salve as alteracoes pendentes antes de abrir a visao de participante."
       )}
    else
      socket = assign(socket, :active_tab, tab)

      socket =
        if tab == "participant" do
          stream(socket, :participant_ballots, socket.assigns.ballots, reset: true)
        else
          socket
        end

      {:noreply, socket}
    end
  end

  def handle_event("validate_event", %{"event" => event_params}, socket) do
    form =
      socket.assigns.current_scope
      |> Events.change_event(socket.assigns.event, event_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, event_form: form, editor_dirty?: true)}
  end

  def handle_event("save_event", %{"event" => event_params}, socket) do
    case Events.update_event(socket.assigns.current_scope, socket.assigns.event, event_params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evento atualizado com sucesso.")
         |> assign_event(event)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, event_form: to_form(changeset, action: :insert))}

      {:error, :closed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos fechados nao podem ser editados.")}

      {:error, :unauthorized} ->
        {:noreply, redirect_to_events(socket)}
    end
  end

  def handle_event("close_ballot", %{"id" => id}, socket) do
    ballot = Events.get_ballot!(socket.assigns.current_scope, socket.assigns.event, id)

    case Events.close_ballot(socket.assigns.current_scope, ballot) do
      {:ok, _ballot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pauta fechada com sucesso.")
         |> assign_event(socket.assigns.event)}

      {:error, :closed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos fechados nao aceitam alteracoes de pauta.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel fechar a pauta.")}
    end
  end

  def handle_event("reopen_ballot", %{"id" => id}, socket) do
    ballot = Events.get_ballot!(socket.assigns.current_scope, socket.assigns.event, id)

    case Events.reopen_ballot(socket.assigns.current_scope, ballot) do
      {:ok, _ballot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pauta reaberta com sucesso.")
         |> assign_event(socket.assigns.event)}

      {:error, :closed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos fechados nao aceitam alteracoes de pauta.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel reabrir a pauta.")}
    end
  end

  @impl true
  def handle_info({:event_changed, _event_name, _event_id}, socket) do
    event = Events.get_event!(socket.assigns.current_scope, socket.assigns.event.id)
    {:noreply, assign_event(socket, event)}
  end

  defp fetch_event(socket, id) do
    {:ok, Events.get_event!(socket.assigns.current_scope, id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  defp assign_event(socket, event) do
    ballots = Events.list_ballots(socket.assigns.current_scope, event)
    results = Events.get_event_results(socket.assigns.current_scope, event)

    assign(socket,
      event: event,
      event_form: event_form(socket.assigns.current_scope, event),
      ballots: ballots,
      can_manage_event?: Events.can_manage_event?(socket.assigns.current_scope, event),
      active_tab: Map.get(socket.assigns, :active_tab, "editor"),
      editor_dirty?: false,
      results_by_ballot: Map.new(results.ballot_results, &{&1.ballot.id, &1})
    )
    |> stream(:ballots, ballots, reset: true)
    |> stream(:participant_ballots, ballots, reset: true)
  end

  defp event_form(scope, event) do
    scope
    |> Events.change_event(event)
    |> to_form()
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

  defp closed_label(%{closed_at: nil}), do: "Nao fechado"

  defp closed_label(%{closed_at: closed_at}) do
    Calendar.strftime(closed_at, "%d/%m/%Y %H:%M")
  end

  defp status_label("open"), do: "Aberto"
  defp status_label("closed"), do: "Fechado"

  defp status_badge_class("open"), do: "bg-emerald-100 text-emerald-800"
  defp status_badge_class("closed"), do: "bg-slate-200 text-slate-700"

  defp ballot_kind_label("multiple_choice"), do: "Multipla escolha"
  defp ballot_kind_label("yes_no_maybe"), do: "Sim, nao ou talvez"

  defp selection_mode_label("multi_choice"), do: "varias respostas"
  defp selection_mode_label(_mode), do: "resposta unica"

  defp ballot_status_label("open"), do: "Aberta"
  defp ballot_status_label("closed"), do: "Fechada"

  defp option_summary(%{kind: "yes_no_maybe"}), do: "Sim, nao e talvez"

  defp option_summary(%{options: options}) do
    active_options = Enum.reject(options, & &1.rejected_at)
    "#{length(active_options)} opcao(oes)"
  end
end
