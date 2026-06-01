defmodule EscalimetroWeb.QRCodeTest do
  use ExUnit.Case, async: true

  alias EscalimetroWeb.QRCode

  test "renders a scannable-sized invite QR SVG with the encoded URL marker" do
    url = "https://example.com/join/token-123"

    svg = QRCode.to_svg(url)

    assert svg =~ ~s(role="img")
    assert svg =~ ~s(aria-label="QRCode do convite")
    assert svg =~ ~s(viewBox="0 0 45 45")
    assert svg =~ ~s(data-url="#{url}")
    assert length(Regex.scan(~r/<rect /, svg)) > 100
  end

  test "escapes URL attributes and falls back for oversized data" do
    url = "https://example.com/join/" <> String.duplicate("a&b", 60)

    svg = QRCode.to_svg(url)

    assert svg =~ ~s(aria-label="QRCode indisponivel")
    assert svg =~ "a&amp;b"
  end
end
