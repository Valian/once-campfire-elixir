defmodule CampfireWeb.Platform do
  @moduledoc """
  The browser and OS a request comes from (Rails `ApplicationPlatform`), as far as the
  notification help text needs: which settings to point at.
  """
  defstruct browser: "",
            os: "",
            ios?: false,
            android?: false,
            windows?: false,
            chrome?: false,
            firefox?: false,
            safari?: false,
            edge?: false

  def from_conn(conn),
    do: conn |> Plug.Conn.get_req_header("user-agent") |> List.first() |> parse()

  def parse(nil), do: %__MODULE__{}

  def parse(ua) do
    edge? = ua =~ ~r/Edg(e|A|iOS)?\//
    firefox? = not edge? and ua =~ ~r/Firefox|FxiOS/
    chrome? = not edge? and not firefox? and ua =~ ~r/Chrome|CriOS/
    safari? = not edge? and not firefox? and not chrome? and ua =~ ~r/Safari/

    browser =
      cond do
        edge? -> "Edge"
        firefox? -> "Firefox"
        chrome? -> "Chrome"
        safari? -> "Safari"
        true -> ""
      end

    os =
      cond do
        ua =~ ~r/Android/ -> "Android"
        ua =~ ~r/iPad/ -> "iPad"
        ua =~ ~r/iPhone/ -> "iPhone"
        ua =~ ~r/Macintosh/ -> "macOS"
        ua =~ ~r/Windows/ -> "Windows"
        ua =~ ~r/CrOS/ -> "ChromeOS"
        ua =~ ~r/Linux/ -> "Linux"
        true -> ""
      end

    %__MODULE__{
      browser: browser,
      os: os,
      ios?: ua =~ ~r/iPhone|iPad/,
      android?: ua =~ ~r/Android/,
      windows?: os == "Windows",
      chrome?: chrome?,
      firefox?: firefox?,
      safari?: safari?,
      edge?: edge?
    }
  end

  def mobile?(%__MODULE__{ios?: ios, android?: android}), do: ios or android
  def desktop?(platform), do: not mobile?(platform)
end
