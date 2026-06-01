defmodule EscalimetroWeb.BallotLive.Form do
  use EscalimetroWeb, :live_view

  alias Escalimetro.Events
  alias Escalimetro.Events.Ballot

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
            navigate={~p"/events/#{@event}"}
            class="inline-flex items-center gap-2 text-sm font-semibold text-primary hover:underline"
          >
            <.icon name="hero-arrow-left" class="size-4" /> {@event.title}
          </.link>
          <h1 class="mt-4 text-3xl font-semibold leading-tight">{@page_title}</h1>
          <p class="mt-2 text-sm leading-6 text-base-content/70">
            Configure tipo de votacao, ordenacao e opcoes que os participantes poderao escolher.
          </p>
        </header>

        <.form
          for={@form}
          id="ballot-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6 rounded-lg border border-base-content/10 bg-base-100 p-5 shadow-sm"
        >
          <.input
            field={@form[:title]}
            type="text"
            label="Titulo da pauta"
            maxlength="160"
            required
            phx-mounted={JS.focus()}
          />

          <.input
            field={@form[:description]}
            type="textarea"
            label="Descricao"
            rows="4"
            maxlength="5000"
          />

          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:kind]}
              id="ballot-kind-input"
              type="select"
              label="Tipo"
              options={[
                {"Multipla escolha", "multiple_choice"},
                {"Sim, nao ou talvez", "yes_no_maybe"}
              ]}
            />
            <.input
              field={@form[:position]}
              type="number"
              label="Posicao"
              min="0"
            />
          </div>

          <div class="grid gap-3 rounded-lg border border-base-content/10 bg-base-200/40 p-4 sm:grid-cols-2">
            <.input
              :if={@selected_kind == "multiple_choice"}
              field={@form[:selection_mode]}
              id="ballot-selection-mode-input"
              type="select"
              label="Modo de selecao"
              options={[
                {"Resposta unica", "single_choice"},
                {"Varias respostas", "multi_choice"}
              ]}
            />

            <div
              :if={@selected_kind == "yes_no_maybe"}
              id="ballot-selection-mode-fixed"
              class="rounded-md bg-base-100 px-3 py-2 text-sm"
            >
              <p class="font-semibold">Modo de selecao</p>
              <p class="mt-1 text-base-content/60">Resposta unica</p>
            </div>

            <.input
              :if={@selected_kind == "multiple_choice"}
              field={@form[:allow_suggestion]}
              type="checkbox"
              label="Permitir sugestoes de novas opcoes"
            />

            <.input
              field={@form[:show_justifications]}
              type="checkbox"
              label="Mostrar justificativas para participantes"
            />
          </div>

          <div :if={@selected_kind == "multiple_choice"} class="space-y-3">
            <div class="flex items-center justify-between gap-4">
              <div>
                <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                  Opcoes
                </h2>
                <p class="mt-1 text-sm text-base-content/60">
                  Pautas de multipla escolha precisam de ao menos duas opcoes.
                </p>
              </div>
              <button
                id="ballot-add-option-button"
                type="button"
                phx-click="add_option"
                class="inline-flex items-center justify-center gap-2 rounded-md border border-base-content/15 px-3 py-2 text-sm font-semibold transition hover:-translate-y-0.5 hover:border-primary/30 hover:text-primary"
              >
                <.icon name="hero-plus" class="size-4" /> Opcao
              </button>
            </div>

            <div class="space-y-3">
              <div :for={{option, index} <- Enum.with_index(@option_rows)} class="flex gap-3">
                <input type="hidden" name={"ballot[options][#{index}][id]"} value={option.id || ""} />
                <input type="hidden" name={"ballot[options][#{index}][position]"} value={index} />
                <div class="min-w-0 flex-1">
                  <.input
                    id={"ballot-option-input-#{index}"}
                    name={"ballot[options][#{index}][label]"}
                    value={option.label}
                    type="text"
                    label={"Opcao #{index + 1}"}
                    maxlength="160"
                  />
                </div>
                <button
                  type="button"
                  phx-click="remove_option"
                  phx-value-index={index}
                  class="mt-7 inline-flex size-10 shrink-0 items-center justify-center rounded-md border border-base-content/15 text-base-content/60 transition hover:-translate-y-0.5 hover:border-error/30 hover:text-error"
                  aria-label="Remover opcao"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>

            <p :if={@options_error} class="flex items-center gap-2 text-sm text-error">
              <.icon name="hero-exclamation-circle" class="size-5" /> {@options_error}
            </p>
          </div>

          <div
            :if={@selected_kind == "yes_no_maybe"}
            class="rounded-lg border border-base-content/10 bg-base-200/40 p-4"
          >
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
              Valores padrao
            </h2>
            <div class="mt-3 flex flex-wrap gap-2">
              <span
                :for={value <- yes_no_maybe_labels()}
                class="rounded-full bg-base-100 px-3 py-1 text-sm font-semibold"
              >
                {value}
              </span>
            </div>
          </div>

          <div class="flex flex-col-reverse gap-3 border-t border-base-content/10 pt-5 sm:flex-row sm:items-center sm:justify-end">
            <.button navigate={~p"/events/#{@event}"} class="btn btn-soft">
              Cancelar
            </.button>
            <.button
              id="ballot-save-button"
              variant="primary"
              phx-disable-with="Salvando..."
              class="btn btn-primary"
            >
              Salvar pauta
            </.button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"event_id" => event_id, "id" => id}, _session, socket) do
    with {:ok, event} <- fetch_event(socket, event_id),
         {:editable, true} <- {:editable, event.status != "closed"} do
      ballot = Events.get_ballot!(socket.assigns.current_scope, event, id)

      {:ok,
       socket
       |> assign(:event, event)
       |> assign(:ballot, ballot)
       |> assign(:page_title, "Editar pauta")
       |> assign_form(ballot, %{})}
    else
      {:editable, false} -> {:ok, redirect_closed_event(socket, event_id)}
      :error -> {:ok, redirect_to_events(socket)}
    end
  end

  def mount(%{"event_id" => event_id}, _session, socket) do
    with {:ok, event} <- fetch_event(socket, event_id),
         {:editable, true} <- {:editable, event.status != "closed"} do
      ballot = %Ballot{position: next_position(socket.assigns.current_scope, event)}

      {:ok,
       socket
       |> assign(:event, event)
       |> assign(:ballot, ballot)
       |> assign(:page_title, "Nova pauta")
       |> assign_form(ballot, %{})}
    else
      {:editable, false} -> {:ok, redirect_closed_event(socket, event_id)}
      :error -> {:ok, redirect_to_events(socket)}
    end
  end

  @impl true
  def handle_event("validate", %{"ballot" => ballot_params}, socket) do
    {:noreply, assign_form(socket, socket.assigns.ballot, ballot_params, :validate)}
  end

  def handle_event("add_option", _params, socket) do
    {:noreply,
     assign(socket, :option_rows, socket.assigns.option_rows ++ [%{id: nil, label: ""}])}
  end

  def handle_event("remove_option", %{"index" => index}, socket) do
    index = parse_index(index)

    option_rows =
      socket.assigns.option_rows
      |> List.delete_at(index)
      |> ensure_option_rows(socket.assigns.selected_kind)

    {:noreply, assign(socket, :option_rows, option_rows)}
  end

  def handle_event("save", %{"ballot" => ballot_params}, socket) do
    save_ballot(socket, socket.assigns.live_action, ballot_params)
  end

  defp save_ballot(socket, :new, ballot_params) do
    case Events.create_ballot(socket.assigns.current_scope, socket.assigns.event, ballot_params) do
      {:ok, _ballot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pauta criada com sucesso.")
         |> push_navigate(to: ~p"/events/#{socket.assigns.event}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign_changeset_form(socket, Map.put(changeset, :action, :insert), ballot_params)}

      {:error, :closed_event} ->
        {:noreply, redirect_closed_event(socket, socket.assigns.event.id)}
    end
  end

  defp save_ballot(socket, :edit, ballot_params) do
    case Events.update_ballot(socket.assigns.current_scope, socket.assigns.ballot, ballot_params) do
      {:ok, _ballot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pauta atualizada com sucesso.")
         |> push_navigate(to: ~p"/events/#{socket.assigns.event}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign_changeset_form(socket, Map.put(changeset, :action, :insert), ballot_params)}

      {:error, :closed_event} ->
        {:noreply, redirect_closed_event(socket, socket.assigns.event.id)}
    end
  end

  defp assign_form(socket, %Ballot{} = ballot, attrs, action \\ nil) do
    changeset =
      socket.assigns.current_scope
      |> Events.change_ballot(ballot, attrs)
      |> maybe_put_action(action)

    assign_changeset_form(socket, changeset, attrs)
  end

  defp assign_changeset_form(socket, %Ecto.Changeset{} = changeset, attrs) do
    selected_kind = Ecto.Changeset.get_field(changeset, :kind) || "multiple_choice"

    option_rows =
      attrs
      |> option_rows_from_attrs()
      |> fallback_option_rows(changeset)
      |> ensure_option_rows(selected_kind)

    socket
    |> assign(:form, to_form(changeset))
    |> assign(:selected_kind, selected_kind)
    |> assign(:option_rows, option_rows)
    |> assign(:options_error, options_error(changeset))
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

  defp redirect_closed_event(socket, event_id) do
    socket
    |> put_flash(:error, "Eventos fechados nao podem receber alteracoes de pauta.")
    |> push_navigate(to: ~p"/events/#{event_id}")
  end

  defp next_position(scope, event) do
    scope
    |> Events.list_ballots(event)
    |> length()
  end

  defp maybe_put_action(changeset, nil), do: changeset
  defp maybe_put_action(changeset, action), do: Map.put(changeset, :action, action)

  defp option_rows_from_attrs(%{"options" => options}), do: normalize_option_rows(options)
  defp option_rows_from_attrs(%{options: options}), do: normalize_option_rows(options)
  defp option_rows_from_attrs(_attrs), do: []

  defp fallback_option_rows([], changeset) do
    case Map.get(changeset.data, :options, []) do
      %Ecto.Association.NotLoaded{} ->
        []

      options ->
        options
        |> Enum.reject(& &1.rejected_at)
        |> Enum.map(&%{id: &1.id, label: &1.label})
    end
  end

  defp fallback_option_rows(rows, _changeset), do: rows

  defp normalize_option_rows(options) when is_map(options) do
    options
    |> Enum.sort_by(fn {key, _value} -> parse_index(key) end)
    |> Enum.map(fn {_key, value} -> value end)
    |> normalize_option_rows()
  end

  defp normalize_option_rows(options) when is_list(options) do
    Enum.map(options, fn option ->
      %{
        id: option_value(option, :id, "id"),
        label: option_value(option, :label, "label") || ""
      }
    end)
  end

  defp normalize_option_rows(_options), do: []

  defp option_value(%{} = option, atom_key, string_key) do
    Map.get(option, atom_key) || Map.get(option, string_key)
  end

  defp option_value(_option, _atom_key, _string_key), do: nil

  defp ensure_option_rows(_rows, "yes_no_maybe"), do: []

  defp ensure_option_rows(rows, _kind) do
    rows
    |> Enum.concat(List.duplicate(%{id: nil, label: ""}, max(2 - length(rows), 0)))
  end

  defp options_error(changeset) do
    changeset.errors
    |> Enum.find_value(fn
      {:options, {message, _opts}} -> message
      _other -> nil
    end)
  end

  defp parse_index(value) when is_integer(value), do: value

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, _rest} -> index
      :error -> 0
    end
  end

  defp parse_index(_value), do: 0

  defp yes_no_maybe_labels, do: ["Sim", "Nao", "Talvez"]
end
