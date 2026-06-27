defmodule EscalimetroWeb.EventLive.Vote do
  use EscalimetroWeb, :live_view

  alias Escalimetro.Events
  alias Escalimetro.Events.BallotOption

  @guest_participant_salt "guest participant"
  @guest_participant_max_age 60 * 60 * 24 * 365

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="mx-auto w-full max-w-3xl space-y-4"
    >
      <section
        id="guest-participant-session"
        phx-hook="GuestParticipantSession"
        data-public-invite-id={@event.public_invite_id}
        class="contents"
      >
      </section>

      <section id={"event-vote-#{@event.id}"} class="space-y-6">
        <header class="rounded-lg border border-base-content/10 bg-base-100 p-5 shadow-sm">
          <p class="text-sm font-semibold uppercase tracking-wide text-primary">Votacao</p>
          <h1 class="mt-2 text-3xl font-semibold leading-tight">{@event.title}</h1>
          <p :if={@event.description} class="mt-3 text-sm leading-6 text-base-content/70">
            {@event.description}
          </p>
        </header>

        <section
          :if={is_nil(@participant)}
          id="participant-identification"
          class="rounded-lg border border-base-content/10 bg-base-100 p-5 shadow-sm"
        >
          <h2 class="text-lg font-semibold">Como devemos identificar seu voto?</h2>
          <.form for={@participant_form} id="participant-form" phx-submit="identify" class="mt-4">
            <.input
              field={@participant_form[:display_name]}
              id="participant-display-name-input"
              label="Nome ou apelido"
              required
            />
            <button id="participant-submit-button" type="submit" class="btn btn-primary mt-2 w-full">
              Entrar na votacao
            </button>
          </.form>
        </section>

        <section :if={@participant} id="voting-area" class="space-y-4">
          <div class="rounded-lg border border-base-content/10 bg-base-100 p-4 text-sm text-base-content/70">
            Votando como
            <span class="font-semibold text-base-content">{@participant.display_name}</span>
          </div>

          <article
            :for={ballot <- @ballots}
            id={"vote-ballot-#{ballot.id}"}
            class="rounded-lg border border-base-content/10 bg-base-100 p-5 shadow-sm"
          >
            <div class="flex flex-wrap items-center gap-2">
              <h2 class="text-xl font-semibold">{ballot.title}</h2>
              <span class={[
                "rounded-full px-2 py-0.5 text-xs font-semibold",
                ballot.status == "open" && "bg-emerald-100 text-emerald-800",
                ballot.status == "closed" && "bg-slate-200 text-slate-700"
              ]}>
                {ballot_status_label(ballot.status)}
              </span>
            </div>
            <p :if={ballot.description} class="mt-2 text-sm leading-6 text-base-content/65">
              {ballot.description}
            </p>

            <div :if={ballot.status == "closed"} class="mt-4 rounded-md bg-base-200 p-3 text-sm">
              Esta pauta foi encerrada. Os resultados seguem visiveis abaixo.
            </div>

            <div :if={ballot.kind == "multiple_choice"} class="mt-4 space-y-3">
              <div
                :for={option <- ballot.options}
                id={"vote-option-#{option.id}"}
                class="rounded-lg border border-base-content/10 p-3"
              >
                <label
                  :if={ballot.status == "open" and @event.status != "completed"}
                  id={"vote-option-control-#{option.id}"}
                  class="flex cursor-pointer items-center justify-between gap-3 rounded-md bg-base-200/70 px-3 py-2 text-sm font-semibold transition hover:bg-base-200"
                >
                  <span class="flex min-w-0 items-center gap-3">
                    <input
                      type="checkbox"
                      id={"vote-option-checkbox-#{option.id}"}
                      class="checkbox checkbox-primary"
                      checked={voted_for_option?(ballot, @participant, option)}
                      phx-click="toggle_option_vote"
                      phx-value-ballot-id={ballot.id}
                      phx-value-option-id={option.id}
                    />
                    <span class="truncate">{option.label}</span>
                  </span>
                  <span class="shrink-0 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary">
                    {Map.get(Events.vote_counts(ballot), option.id, 0)} votos
                  </span>
                </label>

                <div
                  :if={ballot.status != "open" or @event.status == "completed"}
                  class="flex items-center justify-between gap-3"
                >
                  <span class="font-medium">{option.label}</span>
                  <span class="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary">
                    {Map.get(Events.vote_counts(ballot), option.id, 0)} votos
                  </span>
                </div>
              </div>
            </div>

            <div :if={ballot.kind == "yes_no_maybe"} class="mt-4 grid gap-3 sm:grid-cols-3">
              <div
                :for={{value, label} <- yes_no_maybe_options()}
                class="rounded-lg border border-base-content/10 p-3"
              >
                <label
                  :if={ballot.status == "open" and @event.status != "completed"}
                  id={"vote-value-control-#{ballot.id}-#{value}"}
                  class="flex cursor-pointer items-center justify-between gap-3 rounded-md bg-base-200/70 px-3 py-2 text-sm font-semibold transition hover:bg-base-200"
                >
                  <span class="flex min-w-0 items-center gap-3">
                    <input
                      type="checkbox"
                      id={"vote-value-checkbox-#{ballot.id}-#{value}"}
                      class="checkbox checkbox-primary"
                      checked={voted_for_value?(ballot, @participant, value)}
                      phx-click="toggle_value_vote"
                      phx-value-ballot-id={ballot.id}
                      phx-value-vote-value={value}
                    />
                    <span>{label}</span>
                  </span>
                  <span class="shrink-0 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary">
                    {Map.get(Events.vote_counts(ballot), value, 0)}
                  </span>
                </label>

                <div
                  :if={ballot.status != "open" or @event.status == "completed"}
                  class="flex items-center justify-between gap-2"
                >
                  <span class="font-medium">{label}</span>
                  <span class="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary">
                    {Map.get(Events.vote_counts(ballot), value, 0)}
                  </span>
                </div>
              </div>
            </div>

            <.form
              :if={
                ballot.allow_sugestion and ballot.status == "open" and @event.status != "completed"
              }
              for={@suggestion_forms[ballot.id]}
              id={"suggestion-form-#{ballot.id}"}
              phx-submit="suggest_option"
              class="mt-4 grid gap-3 sm:grid-cols-[1fr_auto]"
            >
              <input type="hidden" name="ballot_id" value={ballot.id} />
              <.input
                field={@suggestion_forms[ballot.id][:label]}
                id={"suggestion-label-#{ballot.id}"}
                placeholder="Sugerir nova opcao"
              />
              <button
                id={"suggestion-button-#{ballot.id}"}
                type="submit"
                class="btn btn-soft sm:mt-6"
              >
                Sugerir
              </button>
            </.form>
          </article>
        </section>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"public_invite_id" => public_invite_id}, _session, socket) do
    event = Events.get_public_event_by_invite!(public_invite_id)

    if connected?(socket), do: Events.subscribe_event(event)

    {:ok,
     socket
     |> assign(:event, event)
     |> assign_participant()
     |> assign(:participant_form, to_form(%{}, as: :participant))
     |> assign_ballots()}
  rescue
    Ecto.NoResultsError ->
      {:ok,
       socket
       |> put_flash(:error, "Evento nao encontrado.")
       |> push_navigate(to: ~p"/")}
  end

  @impl true
  def handle_event("identify", %{"participant" => participant_params}, socket) do
    case Events.create_guest_participant(socket.assigns.event, participant_params) do
      {:ok, participant} ->
        {:noreply,
         socket
         |> assign(:participant, participant)
         |> store_guest_participant(participant)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :participant_form, to_form(changeset))}
    end
  end

  def handle_event("restore_participant", %{"token" => token}, socket) do
    case verify_guest_participant_token(socket.assigns.event, token) do
      {:ok, participant} ->
        {:noreply, assign(socket, :participant, participant)}

      :error ->
        {:noreply,
         push_event(socket, "clear_guest_participant", %{
           public_invite_id: socket.assigns.event.public_invite_id
         })}
    end
  end

  def handle_event(
        "toggle_option_vote",
        %{"ballot-id" => ballot_id, "option-id" => option_id},
        socket
      ) do
    ballot = Events.get_ballot_for_event!(socket.assigns.event, ballot_id)
    option = Events.get_ballot_option_for_ballot!(ballot, option_id)

    case Events.toggle_public_option_vote(
           socket.assigns.event,
           socket.assigns.participant,
           ballot,
           option
         ) do
      {:ok, _vote} ->
        {:noreply, assign_ballots(socket)}

      {:error, :closed_ballot} ->
        {:noreply, put_flash(socket, :error, "Esta pauta foi encerrada.")}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Este evento foi concluido.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel alterar o voto.")}
    end
  end

  def handle_event(
        "toggle_value_vote",
        %{"ballot-id" => ballot_id, "vote-value" => value},
        socket
      ) do
    ballot = Events.get_ballot_for_event!(socket.assigns.event, ballot_id)

    case Events.toggle_public_value_vote(
           socket.assigns.event,
           socket.assigns.participant,
           ballot,
           value
         ) do
      {:ok, _vote} ->
        {:noreply, assign_ballots(socket)}

      {:error, :closed_ballot} ->
        {:noreply, put_flash(socket, :error, "Esta pauta foi encerrada.")}

      {:error, :completed_event} ->
        {:noreply, put_flash(socket, :error, "Este evento foi concluido.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel alterar o voto.")}
    end
  end

  def handle_event("toggle_value_vote", _params, socket) do
    {:noreply, put_flash(socket, :error, "Nao foi possivel alterar o voto.")}
  end

  def handle_event(
        "suggest_option",
        %{"ballot_id" => ballot_id, "option" => option_params},
        socket
      ) do
    ballot = Events.get_ballot_for_event!(socket.assigns.event, ballot_id)

    case Events.suggest_ballot_option(
           socket.assigns.event,
           socket.assigns.participant,
           ballot,
           option_params
         ) do
      {:ok, _option} ->
        {:noreply, assign_ballots(socket)}

      {:error, %Ecto.Changeset{} = changeset} ->
        suggestion_forms =
          Map.put(socket.assigns.suggestion_forms, ballot.id, to_form(changeset, as: :option))

        {:noreply, assign(socket, :suggestion_forms, suggestion_forms)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel enviar a sugestao.")}
    end
  end

  @impl true
  def handle_info(%{event: "event_updated"}, socket) do
    {:noreply, assign_ballots(socket)}
  end

  defp assign_ballots(socket) do
    ballots = Events.list_public_ballots(socket.assigns.event)

    suggestion_forms =
      Map.new(ballots, fn ballot ->
        {ballot.id, to_form(Events.change_ballot_option(%{}, %BallotOption{}), as: :option)}
      end)

    assign(socket, ballots: ballots, suggestion_forms: suggestion_forms)
  end

  defp assign_participant(%{assigns: %{current_scope: %{user: user}}} = socket)
       when not is_nil(user) do
    case Events.get_or_create_user_participant(socket.assigns.event, user) do
      {:ok, participant} -> assign(socket, :participant, participant)
      {:error, _changeset} -> assign(socket, :participant, nil)
    end
  end

  defp assign_participant(socket), do: assign(socket, :participant, nil)

  defp store_guest_participant(socket, participant) do
    token =
      Phoenix.Token.sign(
        EscalimetroWeb.Endpoint,
        @guest_participant_salt,
        {socket.assigns.event.id, participant.id}
      )

    push_event(socket, "store_guest_participant", %{
      public_invite_id: socket.assigns.event.public_invite_id,
      token: token,
      display_name: participant.display_name
    })
  end

  defp verify_guest_participant_token(event, token) do
    case Phoenix.Token.verify(
           EscalimetroWeb.Endpoint,
           @guest_participant_salt,
           token,
           max_age: @guest_participant_max_age
         ) do
      {:ok, {event_id, participant_id}} when event_id == event.id ->
        case Events.get_active_public_participant(event, participant_id) do
          nil -> :error
          participant -> {:ok, participant}
        end

      _other ->
        :error
    end
  end

  defp voted_for_option?(ballot, participant, option) do
    Enum.any?(ballot.votes, fn vote ->
      vote.participant_id == participant.id and
        vote.ballot_option_id == option.id and
        is_nil(vote.rejected_at)
    end)
  end

  defp voted_for_value?(ballot, participant, value) do
    Enum.any?(ballot.votes, fn vote ->
      vote.participant_id == participant.id and
        vote.value == value and
        is_nil(vote.ballot_option_id) and
        is_nil(vote.rejected_at)
    end)
  end

  defp ballot_status_label("open"), do: "Aberta"
  defp ballot_status_label("closed"), do: "Encerrada"

  defp yes_no_maybe_options do
    [{"yes", "Sim"}, {"no", "Nao"}, {"maybe", "Talvez"}]
  end
end
