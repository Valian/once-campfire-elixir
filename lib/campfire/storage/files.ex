defmodule Campfire.Storage.Files do
  @moduledoc """
  What Active Storage derives from a file: sanitized filename, sniffed content type, image
  dimensions, and the `Content-Disposition` it is served with.
  """

  ## Filenames (ActiveStorage::Filename)

  @doc "`ActiveStorage::Filename#sanitized`"
  def sanitize(filename) do
    filename
    |> String.replace_invalid("�")
    |> String.trim()
    |> String.replace(
      ["\u202E", "%", "$", "|", ":", ";", "/", "<", ">", "?", "*", "\"", "\t", "\r", "\n", "\\"],
      "-"
    )
  end

  @doc "`{base, extension}` as Rails splits a filename (the extension without its dot, or `\"\"`)."
  def split(filename) do
    case Regex.run(~r/\A(.+?)\.([^.]*)\z/s, filename) do
      [_, base, ext] -> {base, ext}
      nil -> {filename, ""}
    end
  end

  @doc "A filename as a URL path segment (Rails' `escape_path`)."
  def escape_path(segment),
    do: URI.encode(segment, &(URI.char_unreserved?(&1) or &1 in ~c"!$&'()*+,;=:@"))

  # I18n.transliterate's letters that don't decompose into ASCII + combining marks.
  @transliterations %{
    "ß" => "ss",
    "æ" => "ae",
    "Æ" => "AE",
    "ø" => "o",
    "Ø" => "O",
    "œ" => "oe",
    "Œ" => "OE",
    "đ" => "d",
    "Đ" => "D",
    "ł" => "l",
    "Ł" => "L",
    "þ" => "th",
    "Þ" => "Th",
    "ð" => "d",
    "Ð" => "D"
  }

  @doc "`ActionDispatch::Http::ContentDisposition.format`"
  def content_disposition(disposition, filename) do
    ascii =
      filename
      |> String.replace(Map.keys(@transliterations), &@transliterations[&1])
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/[^\x00-\x7F]/u, "?")
      |> percent_escape(~r/[^ A-Za-z0-9!#$+.^_`|~-]/)

    ~s(#{disposition}; filename="#{ascii}"; filename*=UTF-8''#{percent_escape(filename, ~r/[^A-Za-z0-9!#$&+.^_`|~-]/u)})
  end

  defp percent_escape(string, regex) do
    Regex.replace(regex, string, fn char ->
      for <<byte <- char>>, into: "", do: "%" <> Base.encode16(<<byte>>)
    end)
  end

  ## Content types

  @doc """
  The content type Active Storage records: sniffed from the bytes (Marcel's magic numbers)
  when it recognizes them, else by extension, else the declared type.
  """
  def content_type(path, filename, declared) do
    head = read_head(path)

    sniff(head) || by_extension(filename) || clean(declared) || "application/octet-stream"
  end

  defp read_head(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, io} ->
        data = IO.binread(io, 64)
        File.close(io)
        if is_binary(data), do: data, else: ""

      _ ->
        ""
    end
  end

  defp clean(nil), do: nil
  defp clean(""), do: nil

  defp clean(type) do
    case type |> String.split(";") |> hd() |> String.trim() |> String.downcase() do
      "" -> nil
      "application/octet-stream" -> nil
      type -> type
    end
  end

  defp by_extension(filename) do
    case split(filename) do
      {_, ""} ->
        nil

      {_, ext} ->
        ext
        |> String.downcase()
        |> MIME.type()
        |> then(&if(&1 == "application/octet-stream", do: nil, else: &1))
    end
  end

  @doc false
  def sniff(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  def sniff(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: "image/png"
  def sniff(<<"GIF8", v, "a", _::binary>>) when v in [?7, ?9], do: "image/gif"
  def sniff(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  def sniff(<<"BM", _::binary>>), do: "image/bmp"
  def sniff(<<"II*", 0, _::binary>>), do: "image/tiff"
  def sniff(<<"MM", 0, "*", _::binary>>), do: "image/tiff"
  def sniff(<<"%PDF", _::binary>>), do: "application/pdf"
  def sniff(<<0x1A, 0x45, 0xDF, 0xA3, _::binary>>), do: "video/webm"
  def sniff(<<"ID3", _::binary>>), do: "audio/mpeg"

  def sniff(<<_::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>) do
    case brand do
      "qt  " -> "video/quicktime"
      b when b in ["heic", "heix", "hevc", "heim", "heis"] -> "image/heic"
      b when b in ["mif1", "msf1"] -> "image/heif"
      "avif" -> "image/avif"
      b when b in ["M4A ", "M4B "] -> "audio/mp4"
      _ -> "video/mp4"
    end
  end

  def sniff(_), do: nil

  ## Images

  @variable ~w(image/png image/gif image/jpeg image/tiff image/webp image/avif image/heic image/heif)
  @web_image ~w(image/png image/jpeg image/gif image/webp)

  @doc "Rails `variable?` (Campfire drops bmp, ico and psd from the default list)."
  def variable?(content_type), do: content_type in @variable

  @doc "Variants of web images keep their format; other variable images become png."
  def web_image?(content_type), do: content_type in @web_image

  def video?(content_type), do: String.starts_with?(content_type || "", "video/")

  @doc "Image width and height as browsers display them (EXIF orientation applied)."
  def image_dimensions(path) do
    with {:ok, image} <- Vix.Vips.Image.new_from_file(path) do
      {w, h} = {Vix.Vips.Image.width(image), Vix.Vips.Image.height(image)}

      case Vix.Vips.Image.header_value(image, "orientation") do
        {:ok, o} when o in 5..8 -> {:ok, h, w}
        _ -> {:ok, w, h}
      end
    else
      _ -> :error
    end
  end

  # Served inline; everything else is `attachment` (ActiveStorage.content_types_allowed_inline).
  @inline ~w(image/webp image/avif image/png image/gif image/jpeg image/tiff image/bmp
             image/vnd.adobe.photoshop image/vnd.microsoft.icon application/pdf)
  # Served as application/octet-stream (ActiveStorage.content_types_to_serve_as_binary).
  @binary ~w(text/html image/svg+xml application/postscript application/x-shockwave-flash
             text/xml application/xml application/xhtml+xml application/mathml+xml
             text/cache-manifest text/javascript application/javascript)

  def inline?(content_type), do: content_type in @inline

  def serve_as(content_type),
    do:
      if(content_type in @binary or content_type == nil,
        do: "application/octet-stream",
        else: content_type
      )
end
