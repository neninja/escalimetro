defmodule EscalimetroWeb.PageController do
  use EscalimetroWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
