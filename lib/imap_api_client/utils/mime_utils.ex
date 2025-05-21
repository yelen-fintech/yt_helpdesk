defmodule ImapApiClient.Utils.MimeUtils do
  @moduledoc """
  Outils robustes pour décoder tout contenu MIME/texte email, sanitizer en UTF-8,
  et garantir la compatibilité Jason/JSON.
  """

  require Logger

  @charset_map %{
    "utf-8" => :utf8,
    "utf8" => :utf8,
    "us-ascii" => :latin1,
    "iso-8859-1" => :latin1,
    "latin1" => :latin1,
    "windows-1252" => :latin1,
    "iso8859-1" => :latin1
  }

  # -- Header decoding --
  def decode_mime_header(nil), do: nil
  def decode_mime_header(header) when is_binary(header) do
    if String.match?(header, ~r/=\?[\w\-\d]+\?[QB]\?.*?\?=/) do
      decode_encoded_header(header)
    else
      sanitize_string(header)
    end
  end

  defp decode_encoded_header(header) do
    Regex.replace(~r/=\?([\w\-\d]+)\?([QB])\?(.*?)\?=/, header, fn _, charset, encoding, content ->
      decode_content(content, charset, encoding)
    end)
  end

  defp decode_content(content, charset, "Q") do
    content
    |> String.replace("_", " ")
    |> String.replace(~r/=([0-9A-Fa-f]{2})/, fn match ->
        hex = String.slice(match, 1, 2)
        <<String.to_integer(hex, 16)>>
      end)
    |> try_convert_to_utf8(charset)
  end


  defp decode_content(content, charset, "B") do
    case Base.decode64(content) do
      {:ok, decoded} -> try_convert_to_utf8(decoded, charset)
      :error -> Logger.error("Failed to decode Base64 MIME header."); ""
    end
  end

  # -- Charset conversion --
  def try_convert_to_utf8(str, charset) do
    key = String.downcase(to_string(charset))
    charset_atom = Map.get(@charset_map, key, :utf8)
    try do
      :unicode.characters_to_binary(str, charset_atom, :utf8)
    rescue
      _ ->
        Logger.warning("Failed to convert charset=#{inspect(charset)} to utf8, fallback sanitize.")
        sanitize_string(str)
    end
  end

  # -- String sanitation --
  def sanitize_string(nil), do: nil
  def sanitize_string(str) when is_binary(str) do
    if String.valid?(str), do: str, else: filter_invalid_utf8(str)
  end

  # Version safe, se contente de codepoints UTF-8 corrects
  defp filter_invalid_utf8(str) do
    str
    |> String.codepoints()
    |> Enum.filter(&String.valid?/1)
    |> Enum.join("")
  end

   def convert_body_to_utf8(body, charset \\ "utf-8")
    def convert_body_to_utf8(nil, _charset), do: nil
    def convert_body_to_utf8(body, charset) when is_binary(body), do: try_convert_to_utf8(body, charset)
    def convert_body_to_utf8(body, _charset) when is_list(body), do: body |> List.to_string() |> sanitize_string()
    def convert_body_to_utf8(_body, _charset), do: "[UNSUPPORTED_BODY]"


  def deep_sanitize(data) do
    cond do
      is_binary(data) -> sanitize_string(data)
      is_list(data) -> Enum.map(data, &deep_sanitize/1)
      is_map(data) -> Enum.into(data, %{}, fn {k, v} -> {deep_sanitize(k), deep_sanitize(v)} end)
      true -> data
    end
  end

  # (bonus debug)
  def typeof(self) do
    cond do
      is_float(self) -> "float"
      is_number(self) -> "number"
      is_atom(self) -> "atom"
      is_boolean(self) -> "boolean"
      is_binary(self) -> "binary"
      is_function(self) -> "function"
      is_list(self) -> "list"
      is_tuple(self) -> "tuple"
      is_map(self) -> "map"
      is_pid(self) -> "pid"
      is_port(self) -> "port"
      is_reference(self) -> "reference"
      true -> "unknown"
    end
  end
end
