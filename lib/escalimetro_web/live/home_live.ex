defmodule EscalimetroWeb.HomeLive do
  use EscalimetroWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="mx-auto w-full max-w-7xl space-y-4"
    >
      <section
        id="home-landing"
        class="mx-auto grid min-h-[72vh] w-full gap-10 lg:grid-cols-[1fr_0.9fr] lg:items-center"
      >
        <div class="max-w-3xl">
          <p class="text-sm font-semibold uppercase tracking-wide text-primary">
            Votacoes colaborativas para decisoes reais
          </p>
          <h1 class="mt-4 text-4xl font-semibold leading-tight text-base-content sm:text-5xl">
            Escalimetro
          </h1>
          <p class="mt-5 max-w-2xl text-lg leading-8 text-base-content/70">
            Crie um evento, compartilhe um convite e acompanhe escolhas de participantes em tempo
            real para decidir datas, locais, escalas e opcoes com clareza.
          </p>

          <div class="mt-8 flex flex-col gap-3 sm:flex-row">
            <.button
              id="home-login-link"
              navigate={~p"/users/log-in"}
              variant="primary"
              class="btn btn-primary"
            >
              <.icon name="hero-arrow-right-circle" class="size-4" /> Entrar
            </.button>
            <.button
              id="home-register-link"
              navigate={~p"/users/register"}
              class="btn btn-soft"
            >
              <.icon name="hero-user-plus" class="size-4" /> Criar conta
            </.button>
          </div>
        </div>

        <div
          id="home-product-preview"
          class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
        >
          <div class="flex items-center justify-between border-b border-base-content/10 pb-4">
            <div>
              <p class="text-sm font-semibold text-base-content">Evento de planejamento</p>
              <p class="mt-1 text-xs text-base-content/55">4 pautas abertas · 12 participantes</p>
            </div>
            <span class="rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-semibold text-emerald-800">
              Aberto
            </span>
          </div>

          <div class="mt-4 space-y-4">
            <div class="rounded-lg border border-base-content/10 p-4">
              <div class="flex items-center justify-between gap-3">
                <h2 class="font-semibold">Melhor data</h2>
                <span class="rounded-full bg-base-200 px-2 py-1 text-xs font-semibold">
                  18 votos
                </span>
              </div>
              <div class="mt-4 space-y-3">
                <.preview_result label="Sexta, 20h" percent={82} votes="9 votos" primary? />
                <.preview_result label="Sabado, 18h" percent={54} votes="6 votos" />
                <.preview_result label="Domingo, 12h" percent={27} votes="3 votos" />
              </div>
            </div>

            <div class="grid gap-3 sm:grid-cols-2">
              <div class="rounded-lg border border-base-content/10 p-4">
                <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                  Convite
                </p>
                <p class="mt-2 text-sm font-semibold">Link e QRCode</p>
              </div>
              <div class="rounded-lg border border-base-content/10 p-4">
                <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                  Relatorio
                </p>
                <p class="mt-2 text-sm font-semibold">Resumo para WhatsApp</p>
              </div>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :percent, :integer, required: true
  attr :votes, :string, required: true
  attr :primary?, :boolean, default: false

  defp preview_result(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between gap-3 text-sm">
        <span class="font-medium">{@label}</span>
        <span class="text-base-content/60">{@votes}</span>
      </div>
      <div class="mt-2 h-2 overflow-hidden rounded-full bg-base-200">
        <div
          class={[
            "h-full rounded-full transition-[width]",
            @primary? && "bg-primary",
            !@primary? && "bg-base-content/30"
          ]}
          style={"width: #{@percent}%"}
        />
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: ~p"/events")}
  end

  def mount(_params, _session, socket), do: {:ok, socket}
end
