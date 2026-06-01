defmodule EscalimetroWeb.ResultsLive.Show do
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
      <section id="event-results" class="mx-auto w-full max-w-6xl space-y-8">
        <header class="border-b border-base-content/10 pb-6">
          <.link
            navigate={results_back_path(@public?, @event, @public_token)}
            class="inline-flex items-center gap-2 text-sm font-semibold text-primary hover:underline"
          >
            <.icon name="hero-arrow-left" class="size-4" /> {results_back_label(@public?, @event)}
          </.link>

          <div class="mt-4 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div class="max-w-3xl">
              <div class="flex flex-wrap items-center gap-3">
                <h1 class="text-3xl font-semibold leading-tight">Resultados</h1>
                <span class={[
                  "rounded-full px-2.5 py-1 text-xs font-semibold",
                  @event.status == "closed" && "bg-slate-200 text-slate-700",
                  @event.status != "closed" && "bg-emerald-100 text-emerald-800"
                ]}>
                  {event_status_label(@event.status)}
                </span>
              </div>
              <p class="mt-2 text-sm leading-6 text-base-content/70">
                Visao consolidada das opcoes mais votadas, intensidade dos votos, empates e
                rejeicoes registradas.
              </p>
            </div>

            <div class="flex flex-wrap gap-2">
              <button
                id="event-results-summary-generate-button"
                type="button"
                phx-click="generate_summary"
                class="inline-flex items-center justify-center gap-2 rounded-md bg-base-content px-4 py-2 text-sm font-semibold text-base-100 shadow-sm transition hover:-translate-y-0.5 hover:bg-base-content/85"
              >
                <.icon name="hero-clipboard-document-list" class="size-4" /> Gerar resumo
              </button>
              <button
                id="event-results-summary-copy-button"
                type="button"
                phx-hook="CopyInviteUrl"
                data-copy-target="event-results-summary"
                disabled={not @summary_visible?}
                class="inline-flex items-center justify-center gap-2 rounded-md border border-base-content/15 px-4 py-2 text-sm font-semibold transition hover:-translate-y-0.5 hover:border-primary/30 hover:text-primary disabled:cursor-not-allowed disabled:opacity-50"
              >
                <.icon name="hero-clipboard-document" class="size-4" /> Copiar WhatsApp
              </button>
              <button
                id="event-results-export-image-button"
                type="button"
                phx-hook="ExportAsImage"
                data-export-target="event-results-export-area"
                data-export-filename={"escalimetro-#{@event.id}-resultados.svg"}
                class="inline-flex items-center justify-center gap-2 rounded-md border border-base-content/15 px-4 py-2 text-sm font-semibold transition hover:-translate-y-0.5 hover:border-primary/30 hover:text-primary"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Exportar imagem
              </button>
              <.button
                :if={!@public?}
                navigate={~p"/events/#{@event}/moderation"}
                class="btn btn-soft"
              >
                <.icon name="hero-shield-check" class="size-4" /> Moderacao
              </.button>
            </div>
          </div>
        </header>

        <div id="event-results-export-area" class="space-y-8 bg-base-100">
          <dl id="event-results-stats" class="grid gap-4 sm:grid-cols-3">
            <div class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm">
              <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                Pautas
              </dt>
              <dd id="event-results-ballots-count" class="mt-2 text-3xl font-semibold">
                {@report.ballots_count}
              </dd>
            </div>
            <div class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm">
              <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                Votos ativos
              </dt>
              <dd id="event-results-active-votes-count" class="mt-2 text-3xl font-semibold">
                {@report.active_votes_count}
              </dd>
            </div>
            <div class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm">
              <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                Votos rejeitados
              </dt>
              <dd id="event-results-rejected-votes-count" class="mt-2 text-3xl font-semibold">
                {@report.rejected_votes_count}
              </dd>
            </div>
          </dl>

          <section
            :if={@summary_visible?}
            id="event-results-summary-panel"
            class="rounded-lg border border-primary/20 bg-primary/5 p-4 shadow-sm"
          >
            <.input
              id="event-results-summary"
              name="event_results_summary"
              type="textarea"
              label="Resumo consolidado"
              value={@report.summary}
              readonly
              rows="8"
              class="min-h-56 w-full rounded-lg border border-base-content/10 bg-base-100 p-4 font-mono text-sm leading-6 text-base-content shadow-sm focus:border-primary focus:outline-none"
            />
          </section>

          <div id="ballot-results-list" phx-update="stream" class="space-y-4">
            <div
              id="ballot-results-list-empty"
              class="hidden only:block rounded-lg border border-dashed border-base-content/15 p-6 text-center text-sm text-base-content/55"
            >
              Nenhuma pauta criada.
            </div>

            <article
              :for={{id, result} <- @streams.ballot_results}
              id={id}
              class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
            >
              <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2">
                    <h2 class="text-xl font-semibold">{result.ballot.title}</h2>
                    <span class="rounded-full bg-base-200 px-2 py-1 text-xs font-semibold">
                      {ballot_kind_label(result.ballot.kind)}
                    </span>
                    <span class={[
                      "rounded-full px-2 py-1 text-xs font-semibold",
                      result.ballot.status == "open" && "bg-emerald-100 text-emerald-800",
                      result.ballot.status == "closed" && "bg-slate-200 text-slate-700"
                    ]}>
                      {ballot_status_label(result.ballot.status)}
                    </span>
                  </div>
                  <p
                    :if={result.ballot.description}
                    class="mt-2 text-sm leading-6 text-base-content/65"
                  >
                    {result.ballot.description}
                  </p>
                </div>

                <div class="grid min-w-56 grid-cols-2 gap-2 text-sm sm:grid-cols-3 lg:grid-cols-1">
                  <span class="rounded-md bg-base-200/70 px-3 py-2 font-semibold">
                    {result.active_votes_count} ativo(s)
                  </span>
                  <span class="rounded-md bg-base-200/70 px-3 py-2 font-semibold">
                    {result.rejected_votes_count} rejeitado(s)
                  </span>
                  <span
                    :if={result.winner}
                    id={"ballot-result-winner-#{result.ballot.id}"}
                    class="rounded-md bg-primary/10 px-3 py-2 font-semibold text-primary"
                  >
                    {result.winner.label}
                  </span>
                </div>
              </div>

              <div
                :if={result.winner}
                class="mt-5 rounded-lg border border-primary/25 bg-primary/5 p-4"
              >
                <p class="flex items-center gap-2 text-sm font-semibold text-primary">
                  <.icon name="hero-trophy" class="size-4" /> Opcao mais votada
                </p>
                <p class="mt-1 text-lg font-semibold text-base-content">{result.winner.label}</p>
                <p class="mt-1 text-sm text-base-content/65">
                  {result.winner.votes_count} voto(s)
                  <span :if={result.ballot.kind == "multiple_choice"}>
                    - {result.winner.intensity_count} intenso(s)
                  </span>
                  <span :if={result.resolved_by_intensity?}>
                    - desempate por intensidade
                  </span>
                </p>
              </div>

              <div
                :if={result.tie?}
                id={"ballot-result-tie-#{result.ballot.id}"}
                class="mt-5 rounded-lg border border-warning/25 bg-warning/10 p-4"
              >
                <p class="flex items-center gap-2 text-sm font-semibold text-warning">
                  <.icon name="hero-scale" class="size-4" /> Empate
                </p>
                <p class="mt-1 text-sm text-base-content/70">
                  {tied_labels(result)} terminaram com a mesma quantidade de votos e intensidade.
                </p>
              </div>

              <div
                :if={is_nil(result.winner) and not result.tie?}
                id={"ballot-result-empty-#{result.ballot.id}"}
                class="mt-5 rounded-lg border border-dashed border-base-content/15 p-4 text-sm text-base-content/55"
              >
                Sem votos ativos para consolidar.
              </div>

              <div id={"ballot-result-options-#{result.ballot.id}"} class="mt-5 space-y-3">
                <div
                  :for={option <- result.option_results}
                  id={"ballot-result-option-#{result.ballot.id}-#{option.key}"}
                  class={[
                    "rounded-lg border p-4 transition",
                    option.winner && "border-primary/40 bg-primary/5",
                    not option.winner && "border-base-content/10 bg-base-100"
                  ]}
                >
                  <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div class="min-w-0">
                      <div class="flex flex-wrap items-center gap-2">
                        <h3 class="font-semibold">{option.label}</h3>
                        <span
                          :if={option.winner}
                          class="rounded-full bg-primary/10 px-2 py-1 text-xs font-semibold text-primary"
                        >
                          Mais votada
                        </span>
                        <span
                          :if={option.tied}
                          class="rounded-full bg-warning/10 px-2 py-1 text-xs font-semibold text-warning"
                        >
                          Empatada
                        </span>
                        <span
                          :if={option.suggested}
                          class="rounded-full bg-info/10 px-2 py-1 text-xs font-semibold text-info"
                        >
                          Sugestao
                        </span>
                        <span
                          :if={option.rejected}
                          class="rounded-full bg-slate-200 px-2 py-1 text-xs font-semibold text-slate-700"
                        >
                          Opcao rejeitada
                        </span>
                      </div>
                    </div>

                    <div class="flex flex-wrap gap-2 text-xs font-semibold text-base-content/65">
                      <span class="rounded-full bg-base-200 px-2.5 py-1">
                        {option.votes_count} voto(s)
                      </span>
                      <span
                        :if={result.ballot.kind == "multiple_choice"}
                        class="rounded-full bg-base-200 px-2.5 py-1"
                      >
                        {option.intensity_count} intenso(s)
                      </span>
                      <span
                        :if={option.rejected_votes_count > 0}
                        class="rounded-full bg-error/10 px-2.5 py-1 text-error"
                      >
                        {option.rejected_votes_count} rejeitado(s)
                      </span>
                    </div>
                  </div>

                  <div class="mt-4 h-2 overflow-hidden rounded-full bg-base-200">
                    <div
                      class={[
                        "h-full rounded-full transition-[width]",
                        option.winner && "bg-primary",
                        not option.winner && "bg-base-content/30"
                      ]}
                      style={"width: #{option.percent}%"}
                    />
                  </div>

                  <details
                    id={"ballot-result-option-details-#{result.ballot.id}-#{option.key}"}
                    class="mt-4 rounded-md bg-base-200/45 px-3 py-2"
                  >
                    <summary class="cursor-pointer text-sm font-semibold">
                      Votantes
                    </summary>
                    <div class="mt-3 space-y-2">
                      <p :if={option.voter_results == []} class="text-sm text-base-content/55">
                        Nenhum voto ativo nesta opcao.
                      </p>
                      <div
                        :for={vote <- option.voter_results}
                        id={"ballot-result-option-vote-#{vote.id}"}
                        class="rounded-md bg-base-100 px-3 py-2 text-sm"
                      >
                        <div class="flex flex-wrap items-center gap-2">
                          <span class="font-semibold">{vote.participant_name}</span>
                          <span
                            :if={vote.intensity}
                            class="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary"
                          >
                            favorito
                          </span>
                        </div>
                        <p
                          :if={result.ballot.show_justifications and vote.justification}
                          class="mt-1 text-base-content/65"
                        >
                          {vote.justification}
                        </p>
                      </div>
                    </div>
                  </details>
                </div>
              </div>

              <section
                :if={result.rejected_vote_results != []}
                id={"ballot-result-rejected-votes-#{result.ballot.id}"}
                class="mt-5 border-t border-base-content/10 pt-4"
              >
                <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/55">
                  Votos rejeitados
                </h3>
                <div class="mt-3 space-y-2">
                  <p
                    :for={vote <- result.rejected_vote_results}
                    id={"ballot-result-rejected-vote-#{vote.id}"}
                    class="rounded-md bg-error/5 px-3 py-2 text-sm text-base-content/70"
                  >
                    <span class="font-semibold text-base-content">{vote.participant_name}</span>
                    votou em <span class="font-semibold">{vote.value_label}</span>.
                    <span class="text-error">Motivo: {vote.reason}</span>
                  </p>
                </div>
              </section>
            </article>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"event_id" => event_id}, _session, socket) do
    socket = configure_result_stream(socket)

    case fetch_event(socket, event_id) do
      {:ok, event} ->
        if connected?(socket), do: Events.subscribe_event(event)

        {:ok,
         socket
         |> assign(:event, event)
         |> assign(:public?, false)
         |> assign(:public_token, nil)
         |> assign(:summary_visible?, false)
         |> assign_report()}

      :error ->
        {:ok, redirect_to_events(socket)}
    end
  end

  def mount(%{"token" => token}, _session, socket) do
    socket = configure_result_stream(socket)

    case Events.get_public_event_results_by_invite_token(token) do
      {:ok, report} ->
        if connected?(socket), do: Events.subscribe_event(report.event)

        {:ok,
         socket
         |> assign(:event, report.event)
         |> assign(:public?, true)
         |> assign(:public_token, token)
         |> assign(:summary_visible?, false)
         |> assign_report(report)}

      {:error, :invalid_invite} ->
        {:ok,
         socket
         |> put_flash(:error, "Convite invalido ou expirado.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("generate_summary", _params, socket) do
    {:noreply, assign(socket, :summary_visible?, true)}
  end

  @impl true
  def handle_info({:event_changed, _event_name, _event_id}, socket) do
    event =
      if socket.assigns.public? do
        socket.assigns.event
      else
        Events.get_event!(socket.assigns.current_scope, socket.assigns.event.id)
      end

    {:noreply,
     socket
     |> assign(:event, event)
     |> assign_report()}
  end

  defp assign_report(socket) do
    report =
      if socket.assigns.public? do
        Events.get_public_event_results(socket.assigns.event)
      else
        Events.get_event_results(socket.assigns.current_scope, socket.assigns.event)
      end

    assign_report(socket, report)
  end

  defp assign_report(socket, report) do
    socket
    |> assign(:report, Map.delete(report, :ballot_results))
    |> stream(:ballot_results, report.ballot_results, reset: true)
  end

  defp configure_result_stream(socket) do
    stream_configure(socket, :ballot_results,
      dom_id: fn result ->
        "ballot-result-#{result.ballot.id}"
      end
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

  defp event_status_label("open"), do: "Aberto"
  defp event_status_label("closed"), do: "Fechado"

  defp ballot_kind_label("multiple_choice"), do: "Multipla escolha"
  defp ballot_kind_label("yes_no_maybe"), do: "Sim, nao ou talvez"

  defp ballot_status_label("open"), do: "Aberta"
  defp ballot_status_label("closed"), do: "Fechada"

  defp results_back_path(true, _event, token), do: ~p"/join/#{token}"
  defp results_back_path(false, event, _token), do: ~p"/events/#{event}"

  defp results_back_label(true, event), do: event.title
  defp results_back_label(false, event), do: event.title

  defp tied_labels(result) do
    result.tied_options
    |> Enum.map(& &1.label)
    |> Enum.join(", ")
  end
end
