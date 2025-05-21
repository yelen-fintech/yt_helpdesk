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

  # Akismet/courrier vide/null
  def decode_mime_header(nil), do: nil

  # Si header en string, potentiellement codé MIME
  def decode_mime_header(header) when is_binary(header) do
    if String.match?(header, ~r/=\?[\w\-\d]+\?[QB]\?.*?\?=/) do
      decode_encoded_header(header)
    else
      sanitize_string(header)
    end
  end

  # Pour tuple {"Name", "addr@..."}
  def decode_mime_header({name, addr}) do
    "#{decode_mime_header(name)} <#{addr}>"
  end

  # Pour liste d'adresses [{..}, ...]
  def decode_mime_header(list) when is_list(list) do
    list
    |> Enum.map(&decode_mime_header/1)
    |> Enum.join(", ")
  end

  # -- Décodage du header encodé (Q/B), version basique --
  defp decode_encoded_header(header) do
    Regex.replace(~r/=\?([^?]+)\?([QBqb])\?([^?]*)\?=/, header, fn _full, charset, encoding, content ->
      decode_content(content, charset, String.upcase(encoding))
    end)
    |> sanitize_string()
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

  # --- Normalisation body mail ---
  def convert_body_to_utf8(body), do: convert_body_to_utf8(body, "utf-8")
  def convert_body_to_utf8(nil, _charset), do: nil
  def convert_body_to_utf8(body, charset) when is_binary(body), do: try_convert_to_utf8(body, charset)
  def convert_body_to_utf8(body, _charset) when is_list(body), do: body |> List.to_string() |> sanitize_string()
  def convert_body_to_utf8(_body, _charset), do: "[UNSUPPORTED_BODY]"

  # -- Propreté profonde pour Jason --
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

  def safe_to_string(value) do
    cond do
      is_binary(value) -> value
      is_tuple(value) and tuple_size(value) >= 2 and elem(value, 0) == :error ->
        case value do
          {:error, prefix, binary_data} when is_binary(prefix) and is_binary(binary_data) ->
            sanitize_string(prefix <> sanitize_string(binary_data))
          {:error, message} when is_binary(message) ->
            "Erreur: #{sanitize_string(inspect(message))}"
          _ ->
            "Erreur: #{inspect(value)}"
        end
      true -> inspect(value)
    end
  end
end
