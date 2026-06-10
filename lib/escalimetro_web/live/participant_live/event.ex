defmodule EscalimetroWeb.ParticipantLive.Event do
  use EscalimetroWeb, :live_view

  alias Escalimetro.Events
  alias Escalimetro.Events.{Ballot, Topics}
  alias EscalimetroWeb.Presence

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="mx-auto w-full max-w-4xl space-y-4"
    >
      <section id="participant-event" class="mx-auto w-full max-w-3xl space-y-6">
        <header class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <p class="text-sm font-medium uppercase tracking-wide text-primary">Votacao</p>
              <h1 class="mt-1 text-2xl font-semibold leading-tight">{@event.title}</h1>
              <p class="mt-2 text-sm text-base-content/65">
                {participant_name(@participant)}
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              <span class={[
                "rounded-full px-3 py-1 text-sm font-semibold",
                @event.status == "completed" && "bg-slate-200 text-slate-700",
                @event.status != "completed" && "bg-emerald-100 text-emerald-800"
              ]}>
                {event_status(@event.status)}
              </span>
              <span
                id="event-online-count"
                class="rounded-full bg-base-200 px-3 py-1 text-sm font-semibold"
              >
                {@online_count} online
              </span>
            </div>
          </div>
        </header>

        <div id="ballots-voting-list" phx-update="stream" class="space-y-4">
          <div
            id="ballots-voting-list-empty"
            class="hidden only:block rounded-lg border border-dashed border-base-content/15 p-6 text-center text-sm text-base-content/55"
          >
            Nenhuma pauta disponivel.
          </div>

          <article
            :for={{id, ballot} <- @streams.ballots}
            id={id}
            class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
          >
            <% current_vote = Map.get(@votes_by_ballot, ballot.id) %>
            <% blocked_reason = blocked_reason(@event, @participant, ballot) %>

            <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <div class="flex flex-wrap items-center gap-2">
                  <h2 class="text-lg font-semibold">{ballot.title}</h2>
                  <span class={[
                    "rounded-full px-2 py-1 text-xs font-semibold",
                    ballot.status == "open" && "bg-emerald-100 text-emerald-800",
                    ballot.status == "closed" && "bg-slate-200 text-slate-700"
                  ]}>
                    {ballot_status(ballot.status)}
                  </span>
                  <span
                    :if={current_vote && current_vote.rejected_at}
                    class="rounded-full bg-error/10 px-2 py-1 text-xs font-semibold text-error"
                  >
                    Voto rejeitado
                  </span>
                </div>
                <p :if={ballot.description} class="mt-2 text-sm leading-6 text-base-content/65">
                  {ballot.description}
                </p>
                <p :if={blocked_reason} class="mt-2 text-sm font-medium text-base-content/55">
                  {blocked_reason}
                </p>
                <p :if={current_vote && current_vote.rejection_reason} class="mt-2 text-sm text-error">
                  Motivo: {current_vote.rejection_reason}
                </p>
              </div>
            </div>

            <.form
              for={to_form(%{}, as: :vote)}
              id={"vote-form-#{ballot.id}"}
              phx-submit="cast_vote"
              phx-value-ballot-id={ballot.id}
              class="mt-4 space-y-4"
            >
              <input
                :if={current_vote && current_vote.ballot_option_id}
                type="hidden"
                name="vote[ballot_option_id]"
                value={current_vote.ballot_option_id}
              />
              <input
                :if={current_vote && current_vote.value}
                type="hidden"
                name="vote[value]"
                value={current_vote.value}
              />

              <div class="grid gap-2 sm:grid-cols-2">
                <%= if ballot.kind == "multiple_choice" do %>
                  <div :for={option <- ballot.options}>
                    <input
                      type="radio"
                      name="vote[ballot_option_id]"
                      value={option.id}
                      checked={current_vote && current_vote.ballot_option_id == option.id}
                      disabled={not is_nil(blocked_reason)}
                      class="sr-only"
                    />
                    <button
                      id={"vote-option-button-#{option.id}"}
                      type="submit"
                      name="vote[ballot_option_id]"
                      value={option.id}
                      disabled={not is_nil(blocked_reason)}
                      class={[
                        "w-full rounded-lg border px-4 py-3 text-left text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-50",
                        current_vote && current_vote.ballot_option_id == option.id &&
                          "border-primary bg-primary/10 text-primary",
                        (!current_vote || current_vote.ballot_option_id != option.id) &&
                          "border-base-content/10 hover:-translate-y-0.5 hover:border-primary/30"
                      ]}
                    >
                      <span>{option.label}</span>
                      <span
                        :if={option.suggested_by_participant_id}
                        class="mt-1 block text-xs font-normal text-base-content/55"
                      >
                        Sugerido por {suggestion_author(option)}
                      </span>
                    </button>
                  </div>
                <% else %>
                  <div :for={{value, label} <- yes_no_maybe_options()}>
                    <input
                      type="radio"
                      name="vote[value]"
                      value={value}
                      checked={current_vote && current_vote.value == value}
                      disabled={not is_nil(blocked_reason)}
                      class="sr-only"
                    />
                    <button
                      id={"vote-option-button-#{ballot.id}-#{value}"}
                      type="submit"
                      name="vote[value]"
                      value={value}
                      disabled={not is_nil(blocked_reason)}
                      class={[
                        "w-full rounded-lg border px-4 py-3 text-left text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-50",
                        current_vote && current_vote.value == value &&
                          "border-primary bg-primary/10 text-primary",
                        (!current_vote || current_vote.value != value) &&
                          "border-base-content/10 hover:-translate-y-0.5 hover:border-primary/30"
                      ]}
                    >
                      {label}
                    </button>
                  </div>
                <% end %>
              </div>

              <div :if={ballot.kind == "multiple_choice"} class="rounded-lg bg-base-200/50 px-3 py-2">
                <.input
                  id={"vote-intensity-checkbox-#{ballot.id}"}
                  name="vote[intensity]"
                  type="checkbox"
                  label="Quero muito esta opcao"
                  checked={current_vote && current_vote.intensity}
                  disabled={not is_nil(blocked_reason)}
                />
              </div>

              <.input
                id={"vote-justification-input-#{ballot.id}"}
                name="vote[justification]"
                value={(current_vote && current_vote.justification) || ""}
                type="textarea"
                label="Justificativa opcional"
                rows="2"
                maxlength="2000"
                disabled={not is_nil(blocked_reason)}
              />

              <button
                id={"vote-submit-button-#{ballot.id}"}
                type="submit"
                disabled={not is_nil(blocked_reason) or is_nil(current_vote)}
                class="inline-flex w-full items-center justify-center gap-2 rounded-md bg-base-content px-4 py-2 text-sm font-semibold text-base-100 transition hover:-translate-y-0.5 hover:bg-base-content/85 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <.icon name="hero-check-circle" class="size-4" /> Atualizar justificativa
              </button>
            </.form>

            <.form
              :if={ballot.allow_sugestion and is_nil(blocked_reason)}
              for={to_form(%{}, as: :suggestion)}
              id={"suggestion-form-#{ballot.id}"}
              phx-submit="suggest_option"
              phx-value-ballot-id={ballot.id}
              class="mt-5 rounded-lg border border-base-content/10 bg-base-200/40 p-3"
            >
              <.input
                id={"suggestion-label-input-#{ballot.id}"}
                name="suggestion[label]"
                value=""
                type="text"
                label="Sugerir nova opcao"
                maxlength="160"
              />
              <button
                id={"suggestion-submit-button-#{ballot.id}"}
                type="submit"
                class="inline-flex w-full items-center justify-center gap-2 rounded-md border border-primary/30 px-4 py-2 text-sm font-semibold text-primary transition hover:-translate-y-0.5 hover:bg-primary/10"
              >
                <.icon name="hero-plus" class="size-4" /> Enviar sugestao
              </button>
            </.form>

            <div
              :if={ballot.allow_sugestion}
              id={"suggested-options-list-#{ballot.id}"}
              class="mt-4 space-y-2"
            >
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                Sugestoes
              </p>
              <p
                :if={suggested_options(ballot) == []}
                class="text-sm text-base-content/50"
              >
                Nenhuma sugestao enviada.
              </p>
              <p
                :for={option <- suggested_options(ballot)}
                class="rounded-md bg-base-200 px-3 py-2 text-sm"
              >
                {option.label}
                <span class="text-base-content/50">· {suggestion_author(option)}</span>
              </p>
            </div>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"participant_token" => token}, _session, socket) do
    case fetch_participant_event(token) do
      {:ok, data} ->
        socket = configure_ballot_stream(socket)

        if connected?(socket) do
          topic = Topics.event(data.event)
          Events.subscribe_event(data.event)
          Presence.track(self(), topic, "participant:#{data.participant.id}", %{})
        end

        {:ok, assign_participant_event(socket, data)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Convite invalido ou expirado.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("cast_vote", %{"ballot-id" => ballot_id, "vote" => vote_params}, socket) do
    ballot = find_ballot(socket.assigns.ballots, ballot_id)

    case ballot && Events.cast_vote(socket.assigns.participant, ballot, vote_params) do
      {:ok, _vote} ->
        {:noreply,
         socket
         |> put_flash(:info, "Voto registrado.")
         |> reload_participant_event()}

      {:error, reason} when is_atom(reason) ->
        {:noreply, put_flash(socket, :error, vote_error(reason))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel registrar o voto.")}

      nil ->
        {:noreply, put_flash(socket, :error, "Pauta nao encontrada.")}
    end
  end

  def handle_event("suggest_option", %{"ballot-id" => ballot_id, "suggestion" => params}, socket) do
    ballot = find_ballot(socket.assigns.ballots, ballot_id)

    case ballot && Events.suggest_option(socket.assigns.participant, ballot, params) do
      {:ok, _option} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sugestao enviada.")
         |> reload_participant_event()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, suggestion_error(changeset))}

      {:error, reason} when is_atom(reason) ->
        {:noreply, put_flash(socket, :error, vote_error(reason))}

      nil ->
        {:noreply, put_flash(socket, :error, "Pauta nao encontrada.")}
    end
  end

  @impl true
  def handle_info({:event_changed, _event_name, _event_id}, socket) do
    {:noreply, reload_participant_event(socket)}
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign_online_count(socket)}
  end

  defp fetch_participant_event(token) do
    {:ok, Events.get_participant_event!(token)}
  rescue
    Ecto.NoResultsError -> :error
  end

  defp configure_ballot_stream(socket) do
    stream_configure(socket, :ballots, dom_id: fn ballot -> "ballot-card-#{ballot.id}" end)
  end

  defp assign_participant_event(socket, data) do
    socket
    |> assign(:event, data.event)
    |> assign(:participant, data.participant)
    |> assign(:participant_token, data.participant.participant_token)
    |> assign(:ballots, data.ballots)
    |> assign(:votes_by_ballot, data.votes_by_ballot)
    |> assign_online_count()
    |> stream(:ballots, data.ballots, reset: true)
  end

  defp reload_participant_event(socket) do
    socket.assigns.participant_token
    |> Events.get_participant_event!()
    |> then(&assign_participant_event(socket, &1))
  end

  defp assign_online_count(socket) do
    assign(socket, :online_count, map_size(Presence.list(Topics.event(socket.assigns.event))))
  end

  defp find_ballot(ballots, id) do
    parsed_id = parse_id(id)
    Enum.find(ballots, &(&1.id == parsed_id))
  end

  defp blocked_reason(%{status: "completed"}, _participant, _ballot), do: "Evento concluido."
  defp blocked_reason(_event, %{status: "invalidated"}, _ballot), do: "Participacao invalidada."
  defp blocked_reason(_event, _participant, %{status: "closed"}), do: "Pauta fechada."
  defp blocked_reason(_event, _participant, _ballot), do: nil

  defp participant_name(%{kind: "user", user: %{email: email}}), do: email

  defp participant_name(%{display_name: display_name}) when is_binary(display_name),
    do: display_name

  defp participant_name(_participant), do: "Participante"

  defp suggestion_author(%{suggested_by_participant: participant}) when not is_nil(participant),
    do: participant_name(participant)

  defp suggestion_author(_option), do: "participante"

  defp suggested_options(%Ballot{options: options}) do
    Enum.filter(options, & &1.suggested_by_participant_id)
  end

  defp yes_no_maybe_options, do: [{"yes", "Sim"}, {"no", "Nao"}, {"maybe", "Talvez"}]

  defp event_status("completed"), do: "Concluido"
  defp event_status(_status), do: "Aberto"

  defp ballot_status("open"), do: "Aberta"
  defp ballot_status("closed"), do: "Fechada"

  defp vote_error(:completed_event), do: "Evento concluido."
  defp vote_error(:closed_ballot), do: "Pauta fechada."
  defp vote_error(:invalidated_participant), do: "Participacao invalidada."
  defp vote_error(:invalid_ballot_option), do: "Opcao invalida."
  defp vote_error(:invalid_vote_value), do: "Voto invalido."
  defp vote_error(:suggestions_disabled), do: "Sugestoes desabilitadas para esta pauta."
  defp vote_error(_reason), do: "Nao foi possivel concluir a acao."

  defp suggestion_error(changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    case errors do
      %{label: [message | _]} -> "Sugestao invalida: #{message}."
      _ -> "Sugestao invalida."
    end
  end

  defp parse_id(value) when is_integer(value), do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, _rest} -> id
      :error -> nil
    end
  end

  defp parse_id(_value), do: nil
end
