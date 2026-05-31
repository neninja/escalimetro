defmodule EscalimetroWeb.Presence do
  use Phoenix.Presence,
    otp_app: :escalimetro,
    pubsub_server: Escalimetro.PubSub
end
