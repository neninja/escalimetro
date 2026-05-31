defmodule EscalimetroWeb.InviteLive.Admin do
  use EscalimetroWeb, :live_view

  alias Escalimetro.Events
  alias Escalimetro.Events.EventInvite
  alias EscalimetroWeb.QRCode

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="mx-auto w-full max-w-5xl space-y-4"
    >
      <section id="event-invite-admin" class="mx-auto w-full max-w-3xl space-y-6">
        <header class="border-b border-base-content/10 pb-6">
          <.link
            navigate={~p"/events/#{@event}"}
            class="inline-flex items-center gap-2 text-sm font-semibold text-primary hover:underline"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Evento
          </.link>
          <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <p class="text-sm font-medium uppercase tracking-wide text-primary">Convite publico</p>
              <h1 class="mt-1 text-2xl font-semibold leading-tight">{@event.title}</h1>
              <p class="mt-2 text-sm leading-6 text-base-content/65">
                Compartilhe o link ou o QRCode para participantes entrarem sem cadastro.
              </p>
            </div>
            <span class={[
              "rounded-full px-3 py-1 text-sm font-semibold",
              @invite && @invite.status == "active" && "bg-emerald-100 text-emerald-800",
              (!@invite || @invite.status != "active") && "bg-slate-200 text-slate-700"
            ]}>
              {invite_status(@invite)}
            </span>
          </div>
        </header>

        <section class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm">
          <.input
            id="event-invite-url"
            name="invite[url]"
            type="text"
            label="Link publico"
            value={@invite_url || ""}
            readonly
            placeholder="Gere um novo link para copiar"
          />

          <p :if={@invite && is_nil(@invite_url)} class="mt-2 text-sm text-base-content/60">
            Existe um convite ativo. Por seguranca, o token bruto nao e armazenado; gire o convite
            para exibir um novo link copiavel.
          </p>

          <div class="mt-4 flex flex-col gap-2 sm:flex-row">
            <button
              id="event-invite-copy-button"
              type="button"
              phx-hook="CopyInviteUrl"
              data-copy-target="event-invite-url"
              disabled={is_nil(@invite_url)}
              class="inline-flex items-center justify-center gap-2 rounded-md border border-base-content/15 px-4 py-2 text-sm font-semibold transition hover:-translate-y-0.5 hover:border-primary/30 hover:text-primary disabled:cursor-not-allowed disabled:opacity-50"
            >
              <.icon name="hero-clipboard-document" class="size-4" /> Copiar link
            </button>
            <button
              id="event-invite-rotate-button"
              type="button"
              phx-click="rotate_invite"
              class="inline-flex items-center justify-center gap-2 rounded-md bg-base-content px-4 py-2 text-sm font-semibold text-base-100 transition hover:-translate-y-0.5 hover:bg-base-content/85"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Gerar novo link
            </button>
            <button
              id="event-invite-invalidate-button"
              type="button"
              phx-click="invalidate_invite"
              disabled={is_nil(@invite)}
              data-confirm="Invalidar o convite ativo?"
              class="inline-flex items-center justify-center gap-2 rounded-md border border-error/30 px-4 py-2 text-sm font-semibold text-error transition hover:-translate-y-0.5 hover:bg-error/10 disabled:cursor-not-allowed disabled:opacity-50"
            >
              <.icon name="hero-x-circle" class="size-4" /> Invalidar
            </button>
          </div>
        </section>

        <section class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-start">
            <div
              id="event-invite-qrcode"
              data-url={@invite_url || ""}
              class="flex size-56 shrink-0 items-center justify-center rounded-lg border border-base-content/10 bg-white p-3 text-black"
            >
              {Phoenix.HTML.raw(@qrcode_svg || "")}
            </div>
            <div class="space-y-2">
              <h2 class="text-lg font-semibold">QRCode presencial</h2>
              <p class="text-sm leading-6 text-base-content/65">
                Aponte a camera para abrir o mesmo link publico do convite.
              </p>
              <p :if={is_nil(@invite_url)} class="text-sm text-base-content/55">
                Gere um novo link para atualizar o QRCode exibido.
              </p>
            </div>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"event_id" => event_id}, _session, socket) do
    case fetch_event(socket, event_id) do
      {:ok, event} ->
        {:ok, assign_initial_invite(assign(socket, :event, event))}

      :error ->
        {:ok, redirect_to_events(socket)}
    end
  end

  @impl true
  def handle_event("rotate_invite", _params, socket) do
    case Events.rotate_event_invite(socket.assigns.current_scope, socket.assigns.event) do
      {:ok, invite} ->
        {:noreply,
         socket
         |> put_flash(:info, "Novo convite gerado.")
         |> assign_invite(invite)}

      {:error, :unauthorized} ->
        {:noreply, redirect_to_events(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel gerar o convite.")}
    end
  end

  def handle_event("invalidate_invite", _params, socket) do
    case Events.invalidate_event_invite(socket.assigns.current_scope, socket.assigns.event) do
      {:ok, _invite} ->
        {:noreply,
         socket
         |> put_flash(:info, "Convite invalidado.")
         |> assign_invite(nil)}

      {:error, :unauthorized} ->
        {:noreply, redirect_to_events(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel invalidar o convite.")}
    end
  end

  defp assign_initial_invite(socket) do
    case Events.get_active_event_invite(socket.assigns.current_scope, socket.assigns.event) do
      nil ->
        if connected?(socket) do
          case Events.rotate_event_invite(socket.assigns.current_scope, socket.assigns.event) do
            {:ok, invite} -> assign_invite(socket, invite)
            {:error, _reason} -> assign_invite(socket, nil)
          end
        else
          assign_invite(socket, nil)
        end

      %EventInvite{} = invite ->
        assign_invite(socket, invite)
    end
  end

  defp assign_invite(socket, %EventInvite{token: token} = invite) when is_binary(token) do
    invite_url = public_invite_url(token)

    assign(socket,
      invite: invite,
      invite_url: invite_url,
      qrcode_svg: QRCode.to_svg(invite_url)
    )
  end

  defp assign_invite(socket, invite) do
    assign(socket, invite: invite, invite_url: nil, qrcode_svg: nil)
  end

  defp public_invite_url(token) do
    EscalimetroWeb.Endpoint.url() <> ~p"/join/#{token}"
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

  defp invite_status(%EventInvite{status: "active"}), do: "Ativo"
  defp invite_status(_invite), do: "Sem convite ativo"
end
