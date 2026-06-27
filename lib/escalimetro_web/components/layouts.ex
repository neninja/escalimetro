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
    ~H"""
    <main class="px-4 py-12 sm:px-6 lg:px-8">
      <div class={@container_class}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

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
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  attr :id, :string, default: "theme-toggle"

  def theme_toggle(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative flex w-fit flex-row items-center rounded-full border border-base-300 bg-base-200/80 p-0.5 shadow-inner"
    >
      <div class="absolute left-0.5 top-0.5 h-[calc(100%-0.25rem)] w-8 rounded-full border border-base-300/70 bg-base-100 shadow-sm transition-[left] [[data-theme=light]_&]:left-[2.125rem] [[data-theme=dark]_&]:left-[4.125rem]" />

      <button
        id={"#{@id}-system-button"}
        class="relative z-10 flex size-8 cursor-pointer items-center justify-center rounded-full text-base-content/70 transition hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/70"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Use system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        id={"#{@id}-light-button"}
        class="relative z-10 flex size-8 cursor-pointer items-center justify-center rounded-full text-base-content/70 transition hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/70"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Use light theme"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        id={"#{@id}-dark-button"}
        class="relative z-10 flex size-8 cursor-pointer items-center justify-center rounded-full text-base-content/70 transition hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/70"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Use dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
