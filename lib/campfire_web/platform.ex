defmodule CampfireWeb.Platform do
  @moduledoc """
  The little user-agent sniffing the PWA help needs (Rails `ApplicationPlatform`, on top of the
  `useragent` gem): browser family, iOS/Android, desktop OS name.
  """
  defstruct [:browser, :os, ios?: false, android?: false]

  @type t :: %__MODULE__{}

  def from_conn(conn), do: parse(conn |> Plug.Conn.get_req_header("user-agent") |> List.first())

  def parse(nil), do: %__MODULE__{browser: nil, os: nil}

  def parse(ua) when is_binary(ua) do
    %__MODULE__{
      browser: browser(ua),
      os: os(ua),
      ios?: ua =~ ~r/iPhone|iPad/,
      android?: ua =~ ~r/Android/
    }
  end

  # The useragent gem's browser names; Edge and Opera also say "Chrome", iOS Chrome "CriOS".
  defp browser(ua) do
    cond do
      ua =~ ~r/Edg/ -> "Edge"
      ua =~ ~r/OPR|Opera/ -> "Opera"
      ua =~ ~r/Firefox|FxiOS/ -> "Firefox"
      ua =~ ~r/Chrome|CriOS/ -> "Chrome"
      ua =~ ~r/Safari/ -> "Safari"
      true -> nil
    end
  end

  defp os(ua) do
    cond do
      ua =~ ~r/Android/ -> "Android"
      ua =~ ~r/iPad/ -> "iPad"
      ua =~ ~r/iPhone/ -> "iPhone"
      ua =~ ~r/Macintosh/ -> "macOS"
      ua =~ ~r/Windows/ -> "Windows"
      ua =~ ~r/CrOS/ -> "ChromeOS"
      ua =~ ~r/Linux/ -> "Linux"
      true -> nil
    end
  end

  def chrome?(%__MODULE__{browser: b}), do: b == "Chrome"
  def firefox?(%__MODULE__{browser: b}), do: b == "Firefox"
  def safari?(%__MODULE__{browser: b}), do: b == "Safari"
  def edge?(%__MODULE__{browser: b}), do: b == "Edge"
  def desktop?(%__MODULE__{ios?: ios, android?: android}), do: not (ios or android)

  @doc "`platform.browser.capitalize` (empty for unknown browsers)."
  def browser_name(%__MODULE__{browser: b}), do: b || ""
  def os_name(%__MODULE__{os: os}), do: os || ""
end
