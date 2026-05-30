defmodule EscalimetroWeb.ErrorJSONTest do
  use EscalimetroWeb.ConnCase, async: true

  test "renders 404" do
    assert EscalimetroWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert EscalimetroWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
