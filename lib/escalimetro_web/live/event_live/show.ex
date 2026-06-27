defmodule EscalimetroWeb.EventLive.Show do
  use EscalimetroWeb, :live_view

  alias Escalimetro.Events
  alias Escalimetro.Events.{Ballot, BallotOption}

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

        <section id="event-ballots" class="grid gap-6 lg:grid-cols-[1fr_22rem]">
          <div class="space-y-4">
            <div class="flex items-center justify-between gap-3">
              <div>
                <h2 class="text-xl font-semibold">Pautas de votacao</h2>
                <p class="mt-1 text-sm text-base-content/60">
                  Organize as perguntas e opcoes que os participantes vao votar.
                </p>
              </div>
              <.link
                navigate={~p"/events/#{@event.public_invite_id}/vote"}
                class="inline-flex items-center justify-center gap-2 rounded-md border border-base-content/10 px-3 py-2 text-sm font-semibold text-base-content transition hover:bg-base-200"
              >
                <.icon name="hero-arrow-up-right" class="size-4" /> Abrir votacao
              </.link>
            </div>

            <div
              id="ballots-list"
              class="space-y-4"
              phx-update="replace"
            >
              <div
                :if={@ballots == []}
                id="ballots-empty"
                class="rounded-lg border border-dashed border-base-content/20 bg-base-100 p-6 text-sm text-base-content/60"
              >
                Nenhuma pauta criada ainda.
              </div>

              <article
                :for={ballot <- @ballots}
                id={"ballot-#{ballot.id}"}
                class="rounded-lg border border-base-content/10 bg-base-100 p-5 shadow-sm"
              >
                <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-center gap-2">
                      <h3 class="text-lg font-semibold">{ballot.title}</h3>
                      <span class={[
                        "rounded-full px-2 py-0.5 text-xs font-semibold",
                        ballot.status == "open" && "bg-emerald-100 text-emerald-800",
                        ballot.status == "closed" && "bg-slate-200 text-slate-700"
                      ]}>
                        {ballot_status_label(ballot.status)}
                      </span>
                      <span class="rounded-full bg-base-200 px-2 py-0.5 text-xs font-medium text-base-content/70">
                        {ballot_kind_label(ballot.kind)}
                      </span>
                    </div>
                    <p :if={ballot.description} class="mt-2 text-sm leading-6 text-base-content/65">
                      {ballot.description}
                    </p>
                  </div>
                  <button
                    :if={ballot.status == "open" and @event.status != "completed"}
                    id={"close-ballot-#{ballot.id}"}
                    type="button"
                    phx-click="close_ballot"
                    phx-value-id={ballot.id}
                    data-confirm="Encerrar esta pauta?"
                    class="inline-flex items-center justify-center gap-2 rounded-md bg-base-content px-3 py-2 text-sm font-semibold text-base-100 transition hover:bg-base-content/85"
                  >
                    <.icon name="hero-lock-closed" class="size-4" /> Encerrar
                  </button>
                </div>

                <div class="mt-4 space-y-2">
                  <div
                    :if={ballot.kind == "multiple_choice" and ballot.options == []}
                    class="rounded-md bg-base-200/70 px-3 py-2 text-sm text-base-content/60"
                  >
                    Adicione opcoes para liberar votos nesta pauta.
                  </div>

                  <div
                    :for={option <- ballot.options}
                    id={"ballot-option-#{option.id}"}
                    class="flex items-center justify-between gap-3 rounded-md border border-base-content/10 px-3 py-2"
                  >
                    <span class="text-sm font-medium">{option.label}</span>
                    <span class="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary">
                      {Map.get(Events.vote_counts(ballot), option.id, 0)} votos
                    </span>
                  </div>

                  <div
                    :if={ballot.kind == "yes_no_maybe"}
                    id={"ballot-results-#{ballot.id}"}
                    class="grid gap-2 sm:grid-cols-3"
                  >
                    <div
                      :for={{value, label} <- yes_no_maybe_options()}
                      class="rounded-md border border-base-content/10 px-3 py-2"
                    >
                      <div class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                        {label}
                      </div>
                      <div class="mt-1 text-lg font-semibold">
                        {Map.get(Events.vote_counts(ballot), value, 0)}
                      </div>
                    </div>
                  </div>
                </div>

                <.form
                  :if={
                    ballot.kind == "multiple_choice" and ballot.status == "open" and
                      @event.status != "completed"
                  }
                  for={@option_forms[ballot.id]}
                  id={"ballot-option-form-#{ballot.id}"}
                  phx-submit="add_option"
                  class="mt-4 grid gap-3 sm:grid-cols-[1fr_auto]"
                >
                  <input type="hidden" name="ballot_id" value={ballot.id} />
                  <.input
                    field={@option_forms[ballot.id][:label]}
                    id={"ballot-option-label-#{ballot.id}"}
                    placeholder="Nova opcao"
                  />
                  <button
                    id={"add-ballot-option-#{ballot.id}"}
                    type="submit"
                    class="btn btn-primary sm:mt-6"
                  >
                    <.icon name="hero-plus" class="size-4" /> Adicionar
                  </button>
                </.form>
              </article>
            </div>
          </div>

          <aside
            :if={@can_manage_event? and @event.status != "completed"}
            id="new-ballot-panel"
            class="h-fit rounded-lg border border-base-content/10 bg-base-100 p-5 shadow-sm"
          >
            <h2 class="text-lg font-semibold">Nova pauta</h2>
            <.form for={@ballot_form} id="ballot-form" phx-submit="create_ballot" class="mt-4">
              <.input field={@ballot_form[:title]} id="ballot-title-input" label="Titulo" required />
              <.input
                field={@ballot_form[:description]}
                id="ballot-description-input"
                type="textarea"
                label="Descricao"
              />
              <.input
                field={@ballot_form[:kind]}
                id="ballot-kind-input"
                type="select"
                label="Tipo de voto"
                options={[{"Opcoes", "multiple_choice"}, {"Sim / Nao / Talvez", "yes_no_maybe"}]}
              />
              <.input
                field={@ballot_form[:allow_sugestion]}
                id="ballot-allow-sugestion-input"
                type="checkbox"
                label="Permitir sugestoes dos participantes"
              />
              <button id="create-ballot-button" type="submit" class="btn btn-primary mt-2 w-full">
                <.icon name="hero-plus" class="size-4" /> Criar pauta
              </button>
            </.form>
          </aside>
        </section>

        <section
          :if={@can_manage_event?}
          id="participant-vote-review"
          class="space-y-4 rounded-lg border border-base-content/10 bg-base-100 p-5 shadow-sm"
        >
          <div>
            <h2 class="text-xl font-semibold">Votos por participante</h2>
            <p class="mt-1 text-sm text-base-content/60">
              Participantes aparecem na ordem em que entraram. Desmarque um voto para removê-lo.
            </p>
          </div>

          <div
            :if={@participants == []}
            id="participants-empty"
            class="rounded-md bg-base-200/70 px-3 py-2 text-sm text-base-content/60"
          >
            Nenhum participante identificado ainda.
          </div>

          <div id="participants-review-list" class="divide-y divide-base-content/10">
            <article
              :for={participant <- @participants}
              id={"participant-review-#{participant.id}"}
              class="grid gap-3 py-4 sm:grid-cols-[12rem_1fr]"
            >
              <div class="min-w-0">
                <div class="truncate text-sm font-semibold">
                  {participant_label(participant)}
                </div>
                <div class="mt-1 text-xs text-base-content/50">
                  {participant_kind_label(participant.kind)}
                </div>
                <button
                  :if={active_votes(participant) != [] and @event.status != "completed"}
                  id={"participant-clear-votes-#{participant.id}"}
                  type="button"
                  phx-click="remove_participant_votes"
                  phx-value-id={participant.id}
                  data-confirm="Ignorar todos os votos deste participante?"
                  class="mt-3 inline-flex items-center gap-1.5 rounded-md border border-error/20 px-2.5 py-1.5 text-xs font-semibold text-error transition hover:bg-error/10"
                >
                  <.icon name="hero-x-mark" class="size-3.5" /> Ignorar votos
                </button>
              </div>

              <div class="flex flex-wrap gap-2">
                <div
                  :if={active_votes(participant) == []}
                  class="rounded-md bg-base-200/70 px-3 py-2 text-sm text-base-content/60"
                >
                  Sem votos ativos.
                </div>

                <label
                  :for={vote <- active_votes(participant)}
                  id={"participant-vote-#{vote.id}"}
                  class="flex cursor-pointer items-center gap-2 rounded-md border border-base-content/10 bg-base-100 px-3 py-2 text-sm font-medium transition hover:bg-base-200"
                >
                  <input
                    type="checkbox"
                    id={"participant-vote-checkbox-#{vote.id}"}
                    class="checkbox checkbox-primary checkbox-sm"
                    checked
                    disabled={@event.status == "completed"}
                    phx-click="remove_vote"
                    phx-value-id={vote.id}
                  />
                  <span>{admin_vote_label(vote)}</span>
                </label>
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

        {:ok,
         socket
         |> assign_event(event)
         |> assign_ballot_form()
         |> assign_ballots()
         |> assign_participants()}

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
         |> assign_event(event)
         |> assign_ballots()
         |> assign_participants()}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Este evento ja esta concluido.")}

      {:error, :unauthorized} ->
        {:noreply, redirect_to_events(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel concluir o evento.")}
    end
  end

  @impl true
  def handle_event("create_ballot", %{"ballot" => ballot_params}, socket) do
    case Events.create_ballot(socket.assigns.current_scope, socket.assigns.event, ballot_params) do
      {:ok, _ballot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pauta criada.")
         |> assign_ballot_form()
         |> assign_ballots()
         |> assign_participants()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :ballot_form, to_form(changeset))}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos concluidos nao aceitam novas pautas.")}

      {:error, :unauthorized} ->
        {:noreply, redirect_to_events(socket)}
    end
  end

  def handle_event("add_option", %{"ballot_id" => ballot_id, "option" => option_params}, socket) do
    ballot = Events.get_ballot_for_event!(socket.assigns.event, ballot_id)

    case Events.create_ballot_option(socket.assigns.current_scope, ballot, option_params) do
      {:ok, _option} ->
        {:noreply, socket |> assign_ballots() |> assign_participants()}

      {:error, %Ecto.Changeset{} = changeset} ->
        option_forms =
          Map.put(socket.assigns.option_forms, ballot.id, to_form(changeset, as: :option))

        {:noreply, assign(socket, :option_forms, option_forms)}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos concluidos nao aceitam novas opcoes.")}
    end
  end

  def handle_event("close_ballot", %{"id" => ballot_id}, socket) do
    ballot = Events.get_ballot_for_event!(socket.assigns.event, ballot_id)

    case Events.close_ballot(socket.assigns.current_scope, ballot) do
      {:ok, _ballot} ->
        {:noreply, socket |> assign_ballots() |> assign_participants()}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos concluidos nao podem ser alterados.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel encerrar a pauta.")}
    end
  end

  def handle_event("remove_vote", %{"id" => vote_id}, socket) do
    case Events.delete_vote(socket.assigns.current_scope, socket.assigns.event, vote_id) do
      {:ok, _vote} ->
        {:noreply, socket |> assign_ballots() |> assign_participants()}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos concluidos nao podem ser alterados.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel remover o voto.")}
    end
  end

  def handle_event("remove_participant_votes", %{"id" => participant_id}, socket) do
    case Events.delete_participant_votes(
           socket.assigns.current_scope,
           socket.assigns.event,
           participant_id
         ) do
      {:ok, :deleted} ->
        {:noreply, socket |> assign_ballots() |> assign_participants()}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos concluidos nao podem ser alterados.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel remover os votos.")}
    end
  end

  @impl true
  def handle_info(%{event: "event_updated"}, socket) do
    {:noreply, socket |> assign_ballots() |> assign_participants()}
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

  defp assign_ballots(socket) do
    ballots = Events.list_ballots(socket.assigns.current_scope, socket.assigns.event)
    option_forms = Map.new(ballots, fn ballot -> {ballot.id, option_form(%BallotOption{})} end)

    assign(socket, ballots: ballots, option_forms: option_forms)
  end

  defp assign_participants(socket) do
    assign(
      socket,
      :participants,
      Events.list_event_participants_for_review(
        socket.assigns.current_scope,
        socket.assigns.event
      )
    )
  end

  defp assign_ballot_form(socket) do
    changeset =
      Events.change_ballot(socket.assigns.current_scope, %Ballot{
        event_id: socket.assigns.event.id,
        position: length(socket.assigns[:ballots] || [])
      })

    assign(socket, :ballot_form, to_form(changeset))
  end

  defp option_form(%BallotOption{} = option) do
    to_form(Events.change_ballot_option(%{}, option), as: :option)
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

  defp ballot_status_label("open"), do: "Aberta"
  defp ballot_status_label("closed"), do: "Encerrada"

  defp ballot_kind_label("multiple_choice"), do: "Opcoes"
  defp ballot_kind_label("yes_no_maybe"), do: "Sim / Nao / Talvez"

  defp yes_no_maybe_options do
    [{"yes", "Sim"}, {"no", "Nao"}, {"maybe", "Talvez"}]
  end

  defp active_votes(participant) do
    participant.votes
    |> Enum.reject(& &1.rejected_at)
    |> Enum.sort_by(fn vote ->
      {vote.ballot.position, DateTime.to_unix(vote.ballot.inserted_at), vote.id}
    end)
  end

  defp participant_label(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp participant_label(%{user: %{email: email}}), do: email
  defp participant_label(_participant), do: "Participante"

  defp participant_kind_label("guest"), do: "Convidado"
  defp participant_kind_label("user"), do: "Usuario"

  defp admin_vote_label(%{ballot: ballot, ballot_option: %{label: label}}) do
    "#{ballot.title}: #{label}"
  end

  defp admin_vote_label(%{ballot: ballot, value: value}) do
    "#{ballot.title}: #{value_label(value)}"
  end

  defp value_label("yes"), do: "Sim"
  defp value_label("no"), do: "Nao"
  defp value_label("maybe"), do: "Talvez"
end
