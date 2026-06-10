defmodule EscalimetroWeb.EventLive.Form do
  use EscalimetroWeb, :live_view

  alias Escalimetro.Events
  alias Escalimetro.Events.Event

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="mx-auto w-full max-w-7xl space-y-4"
    >
      <section class="mx-auto w-full max-w-3xl space-y-8">
        <header class="border-b border-base-content/10 pb-6">
          <.link
            navigate={~p"/events"}
            class="inline-flex items-center gap-2 text-sm font-semibold text-primary hover:underline"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Eventos
          </.link>
          <h1 class="mt-4 text-3xl font-semibold leading-tight">{@page_title}</h1>
          <p class="mt-2 text-sm leading-6 text-base-content/70">
            Defina as informacoes principais antes de criar pautas e convidar participantes.
          </p>
        </header>

        <.form
          for={@form}
          id="event-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6 rounded-lg border border-base-content/10 bg-base-100 p-5 shadow-sm"
        >
          <.input
            field={@form[:title]}
            id="event-title-input"
            type="text"
            label="Titulo"
            maxlength="160"
            required
            phx-mounted={JS.focus()}
          />

          <.input
            field={@form[:description]}
            type="textarea"
            label="Descricao"
            rows="5"
            maxlength="5000"
          />

          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:scheduled_at]}
              type="datetime-local"
              label="Data e hora"
            />
            <.input
              field={@form[:location]}
              type="text"
              label="Local"
              maxlength="160"
            />
          </div>

          <div class="flex flex-col-reverse gap-3 border-t border-base-content/10 pt-5 sm:flex-row sm:items-center sm:justify-end">
            <.button navigate={back_path(@event)} class="btn btn-soft">
              Cancelar
            </.button>
            <.button
              id="event-save-button"
              variant="primary"
              phx-disable-with="Salvando..."
              class="btn btn-primary"
            >
              Salvar evento
            </.button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case fetch_event(socket, id) do
      {:ok, %Event{status: "completed"} = event} ->
        {:ok,
         socket
         |> put_flash(:error, "Eventos concluidos nao podem ser editados.")
         |> push_navigate(to: ~p"/events/#{event}")}

      {:ok, event} ->
        changeset = Events.change_event(socket.assigns.current_scope, event)

        {:ok,
         socket
         |> assign(:page_title, "Editar evento")
         |> assign(:event, event)
         |> assign(:form, to_form(changeset))}

      :error ->
        {:ok, redirect_to_events(socket)}
    end
  end

  def mount(_params, _session, socket) do
    event = %Event{}
    changeset = Events.change_event(socket.assigns.current_scope, event)

    {:ok,
     socket
     |> assign(:page_title, "Novo evento")
     |> assign(:event, event)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    form =
      socket.assigns.current_scope
      |> Events.change_event(socket.assigns.event, event_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"event" => event_params}, socket) do
    save_event(socket, socket.assigns.live_action, event_params)
  end

  defp save_event(socket, :new, event_params) do
    case Events.create_event(socket.assigns.current_scope, event_params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evento criado com sucesso.")
         |> push_navigate(to: ~p"/events/#{event}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Voce precisa entrar para criar eventos.")}
    end
  end

  defp save_event(socket, :edit, event_params) do
    case Events.update_event(socket.assigns.current_scope, socket.assigns.event, event_params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evento atualizado com sucesso.")
         |> push_navigate(to: ~p"/events/#{event}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}

      {:error, :completed_event} ->
        {:noreply,
         socket
         |> put_flash(:error, "Eventos concluidos nao podem ser editados.")
         |> push_navigate(to: ~p"/events/#{socket.assigns.event}")}

      {:error, :unauthorized} ->
        {:noreply, redirect_to_events(socket)}
    end
  end

  defp fetch_event(socket, id) do
    {:ok, Events.get_event!(socket.assigns.current_scope, id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  defp redirect_to_events(socket) do
    socket
    |> put_flash(:error, "Evento nao encontrado ou sem acesso.")
    |> push_navigate(to: ~p"/events")
  end

  defp back_path(%Event{id: nil}), do: ~p"/events"
  defp back_path(%Event{} = event), do: ~p"/events/#{event}"
end
