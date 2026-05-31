defmodule Escalimetro.Events.Topics do
  @moduledoc false

  def event(%{id: id}), do: event(id)
  def event(id), do: "events:#{id}"
end
