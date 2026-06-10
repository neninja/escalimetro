defmodule EscalimetroWeb.ModerationLive.Index do
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
              <h1 class="text-3xl font-semibold leading-tight">Moderacao</h1>
              <p class="mt-2 text-sm leading-6 text-base-content/70">
                Rejeite ou restaure votos mantendo historico e transparencia.
              </p>
            </div>
            <.button navigate={~p"/events/#{@event}/participants"} class="btn btn-soft">
              <.icon name="hero-users" class="size-4" /> Participantes
            </.button>
          </div>
        </header>

        <div id="moderation-votes-list" class="space-y-3">
          <p
            :if={@votes == []}
            class="rounded-lg border border-dashed border-base-content/15 p-4 text-sm text-base-content/55"
          >
            Nenhum voto registrado.
          </p>

          <article
            :for={vote <- @votes}
            id={"moderation-vote-#{vote.id}"}
            class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
          >
            <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
              <div class="min-w-0 space-y-2">
                <div class="flex flex-wrap items-center gap-2">
                  <h2 class="font-semibold">{vote.ballot.title}</h2>
                  <span class={[
                    "rounded-full px-2 py-1 text-xs font-semibold",
                    is_nil(vote.rejected_at) && "bg-emerald-100 text-emerald-800",
                    not is_nil(vote.rejected_at) && "bg-slate-200 text-slate-700"
                  ]}>
                    {vote_status(vote)}
                  </span>
                </div>
                <p class="text-sm text-base-content/65">
                  {participant_name(vote.participant)} votou em {vote_value(vote)}
                </p>
                <p :if={vote.justification} class="text-sm text-base-content/60">
                  Justificativa: {vote.justification}
                </p>
                <p :if={vote.rejection_reason} class="text-sm text-error">
                  Motivo da rejeicao: {vote.rejection_reason}
                </p>
              </div>

              <div class="w-full shrink-0 lg:w-80">
                <.form
                  :if={is_nil(vote.rejected_at) and @event.status != "completed"}
                  for={to_form(%{}, as: :vote)}
                  id={"vote-reject-form-#{vote.id}"}
                  phx-submit="reject_vote"
                  phx-value-id={vote.id}
                  class="flex flex-col gap-2"
                >
                  <.input
                    name="vote[rejection_reason]"
                    value=""
                    type="text"
                    label="Motivo opcional"
                    maxlength="500"
                  />
                  <button
                    id={"vote-reject-button-#{vote.id}"}
                    type="submit"
                    class="inline-flex items-center justify-center gap-2 rounded-md border border-error/30 px-3 py-2 text-sm font-semibold text-error transition hover:-translate-y-0.5 hover:bg-error/10"
                  >
                    <.icon name="hero-x-circle" class="size-4" /> Rejeitar voto
                  </button>
                </.form>

                <button
                  :if={not is_nil(vote.rejected_at) and @event.status != "completed"}
                  id={"vote-restore-button-#{vote.id}"}
                  type="button"
                  phx-click="restore_vote"
                  phx-value-id={vote.id}
                  class="inline-flex w-full items-center justify-center gap-2 rounded-md border border-emerald-500/30 px-3 py-2 text-sm font-semibold text-emerald-700 transition hover:-translate-y-0.5 hover:bg-emerald-500/10"
                >
                  <.icon name="hero-arrow-path" class="size-4" /> Restaurar voto
                </button>
              </div>
            </div>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"event_id" => event_id}, _session, socket) do
    case fetch_event(socket, event_id) do
      {:ok, event} ->
        {:ok, assign_votes(assign(socket, :event, event))}

      :error ->
        {:ok, redirect_to_events(socket)}
    end
  end

  @impl true
  def handle_event("reject_vote", %{"id" => id, "vote" => vote_params}, socket) do
    vote = find_vote(socket.assigns.votes, id)

    case vote && Events.reject_vote(socket.assigns.current_scope, vote, vote_params) do
      {:ok, _vote} ->
        {:noreply,
         socket
         |> put_flash(:info, "Voto rejeitado com sucesso.")
         |> assign_votes()}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos concluidos nao aceitam moderacao.")}

      _other ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel rejeitar voto.")}
    end
  end

  def handle_event("restore_vote", %{"id" => id}, socket) do
    vote = find_vote(socket.assigns.votes, id)

    case vote && Events.restore_vote(socket.assigns.current_scope, vote) do
      {:ok, _vote} ->
        {:noreply,
         socket
         |> put_flash(:info, "Voto restaurado com sucesso.")
         |> assign_votes()}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Eventos concluidos nao aceitam moderacao.")}

      {:error, :invalidated_participant} ->
        {:noreply,
         put_flash(socket, :error, "Participante invalidado nao pode ter voto restaurado.")}

      _other ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel restaurar voto.")}
    end
  end

  defp assign_votes(socket) do
    assign(socket, :votes, Events.list_votes(socket.assigns.current_scope, socket.assigns.event))
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

  defp find_vote(votes, id) do
    parsed_id = parse_id(id)
    Enum.find(votes, &(&1.id == parsed_id))
  end

  defp participant_name(%{kind: "user", user: %{email: email}}), do: email

  defp participant_name(%{display_name: display_name}) when is_binary(display_name),
    do: display_name

  defp participant_name(_participant), do: "Participante"

  defp vote_value(%{ballot_option: %{label: label}}), do: label
  defp vote_value(%{value: "yes"}), do: "Sim"
  defp vote_value(%{value: "no"}), do: "Nao"
  defp vote_value(%{value: "maybe"}), do: "Talvez"
  defp vote_value(_vote), do: "valor nao informado"

  defp vote_status(%{rejected_at: nil}), do: "Ativo"
  defp vote_status(_vote), do: "Rejeitado"

  defp parse_id(value) when is_integer(value), do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, _rest} -> id
      :error -> nil
    end
  end

  defp parse_id(_value), do: nil
end
