defmodule EscalimetroWeb.InviteLive.Join do
  use EscalimetroWeb, :live_view

  alias Escalimetro.Events

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="mx-auto w-full max-w-3xl space-y-4"
    >
      <section class="mx-auto flex min-h-[60vh] w-full max-w-lg flex-col justify-center">
        <div
          :if={@invalid_invite?}
          id="invite-invalid-state"
          class="rounded-lg border border-error/20 bg-error/5 p-6 text-center"
        >
          <div class="mx-auto flex size-12 items-center justify-center rounded-full bg-error/10 text-error">
            <.icon name="hero-link-slash" class="size-6" />
          </div>
          <h1 class="mt-4 text-xl font-semibold">Convite invalido</h1>
          <p class="mt-2 text-sm leading-6 text-base-content/65">
            Este link pode ter expirado, sido substituido ou invalidado pela organizacao.
          </p>
        </div>

        <div
          :if={not @invalid_invite?}
          class="rounded-lg border border-base-content/10 bg-base-100 p-6 shadow-sm"
        >
          <p class="text-sm font-medium uppercase tracking-wide text-primary">Entrada do evento</p>
          <h1 class="mt-1 text-2xl font-semibold leading-tight">{@event.title}</h1>
          <p class="mt-2 text-sm leading-6 text-base-content/65">
            Informe como voce quer aparecer na votacao.
          </p>

          <.form
            for={@form}
            id="guest-identification-form"
            phx-submit="enter_event"
            class="mt-5 space-y-4"
          >
            <.input
              field={@form[:display_name]}
              id="guest-display-name-input"
              type="text"
              label="Nome ou apelido"
              minlength="2"
              maxlength="160"
              required
            />
            <button
              id="guest-enter-event-button"
              type="submit"
              class="inline-flex w-full items-center justify-center gap-2 rounded-md bg-base-content px-4 py-2 text-sm font-semibold text-base-100 transition hover:-translate-y-0.5 hover:bg-base-content/85"
            >
              <.icon name="hero-arrow-right-circle" class="size-4" /> Entrar na votacao
            </button>
          </.form>

          <.link
            id="public-results-link"
            navigate={~p"/results/#{@token}"}
            class="mt-3 inline-flex w-full items-center justify-center gap-2 rounded-md border border-base-content/15 px-4 py-2 text-sm font-semibold transition hover:-translate-y-0.5 hover:border-primary/30 hover:text-primary"
          >
            <.icon name="hero-chart-bar" class="size-4" /> Ver resultados
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Events.get_active_invite_by_token(token) do
      nil ->
        {:ok,
         assign(socket,
           token: token,
           invite: nil,
           event: nil,
           invalid_invite?: true,
           form: to_form(Events.change_guest_identification(), as: :guest)
         )}

      invite ->
        socket =
          assign(socket,
            token: token,
            invite: invite,
            event: invite.event,
            invalid_invite?: false,
            form: to_form(Events.change_guest_identification(), as: :guest)
          )

        maybe_enter_authenticated_user(socket, invite)
    end
  end

  @impl true
  def handle_event("enter_event", %{"guest" => guest_params}, socket) do
    case Events.enter_event_invite(
           socket.assigns.current_scope,
           socket.assigns.invite,
           guest_params
         ) do
      {:ok, participant} ->
        {:noreply, push_navigate(socket, to: ~p"/events/public/#{participant.participant_token}")}

      {:error, :invalid_invite} ->
        {:noreply, assign(socket, invalid_invite?: true, invite: nil, event: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(%{changeset | action: :insert}, as: :guest))}
    end
  end

  defp maybe_enter_authenticated_user(
         %{assigns: %{current_scope: %{user: _user}}} = socket,
         invite
       ) do
    case Events.enter_event_invite(socket.assigns.current_scope, invite) do
      {:ok, participant} ->
        {:ok, push_navigate(socket, to: ~p"/events/public/#{participant.participant_token}")}

      {:error, :invalid_invite} ->
        {:ok, assign(socket, invalid_invite?: true, invite: nil, event: nil)}

      {:error, _changeset} ->
        {:ok, put_flash(socket, :error, "Nao foi possivel entrar no evento.")}
    end
  end

  defp maybe_enter_authenticated_user(socket, _invite), do: {:ok, socket}
end
