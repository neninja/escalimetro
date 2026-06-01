defmodule EscalimetroWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EscalimetroWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :container_class, :any, default: "mx-auto max-w-2xl space-y-4"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :stop_impersonation_form, to_form(%{}, as: :impersonation))

    ~H"""
    <div
      :if={impersonating?(@current_scope)}
      id="impersonation-banner"
      class="flex flex-col gap-3 border-b border-amber-300/60 bg-amber-100 px-4 py-3 text-sm text-amber-950 sm:flex-row sm:items-center sm:justify-between sm:px-6 lg:px-8"
    >
      <div class="flex items-center gap-2">
        <.icon name="hero-eye" class="size-4 shrink-0" />
        <p>
          Impersonando <strong>{@current_scope.user.email}</strong>
          por <strong>{@current_scope.impersonator_user.email}</strong>
        </p>
      </div>
      <.form
        for={@stop_impersonation_form}
        id="stop-impersonation-form"
        action={~p"/backoffice/impersonation"}
        method="delete"
      >
        <button
          id="stop-impersonation-button"
          type="submit"
          class="inline-flex items-center justify-center gap-2 rounded-md border border-amber-900/20 bg-white/70 px-3 py-1.5 text-sm font-semibold text-amber-950 transition hover:-translate-y-0.5 hover:bg-white"
        >
          <.icon name="hero-arrow-uturn-left" class="size-4" /> Encerrar impersonacao
        </button>
      </.form>
    </div>

    <header class="border-b border-base-content/10 bg-base-100/95 px-4 py-3 sm:px-6 lg:px-8">
      <nav class="mx-auto flex max-w-7xl items-center justify-between gap-4" aria-label="Principal">
        <.link navigate={~p"/"} class="flex items-center gap-3">
          <span class="flex size-9 items-center justify-center rounded-md bg-base-content text-sm font-semibold text-base-100">
            E
          </span>
          <span class="text-sm font-semibold tracking-normal">Escalimetro</span>
        </.link>

        <div class="flex items-center gap-2">
          <.theme_toggle />

          <%= if @current_scope && @current_scope.user do %>
            <.link navigate={~p"/events"} class="btn btn-ghost btn-sm">Eventos</.link>
            <.link
              :if={@current_scope.user.system_admin}
              navigate={~p"/backoffice"}
              class="btn btn-ghost btn-sm"
            >
              Backoffice
            </.link>
            <.link navigate={~p"/users/settings"} class="btn btn-ghost btn-sm">Conta</.link>
            <.link href={~p"/users/log-out"} method="delete" class="btn btn-soft btn-sm">Sair</.link>
          <% else %>
            <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">Entrar</.link>
            <.link navigate={~p"/users/register"} class="btn btn-primary btn-sm">Criar conta</.link>
          <% end %>
        </div>
      </nav>
    </header>

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class={@container_class}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  defp impersonating?(%{impersonator_user: %{}}), do: true
  defp impersonating?(_current_scope), do: false

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Sem conexao")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Tentando reconectar")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Algo deu errado")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Tentando reconectar")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
