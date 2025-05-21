defmodule ImapApiClient.Utils.MimeUtils do
  @moduledoc """
  Utilitaires pour le traitement des données MIME et l'encodage de caractères.
  Ce module fournit des fonctions pour décoder les en-têtes MIME, sanitiser les
  chaînes pour garantir un encodage UTF-8 valide.
  """

  require Logger

  @doc """
  Décode les en-têtes MIME encodés.
  """
  def decode_mime_header(nil), do: nil
  def decode_mime_header(header) when is_binary(header) do
    if String.match?(header, ~r/=\?[\w-]+\?[QB]\?.*?\?=/) do
      decode_encoded_header(header)
    else
      sanitize_string(header)
    end
  end

  defp decode_encoded_header(header) do
    Regex.replace(~r/=\?([\w-]+)\?([QB])\?(.*?)\?=/, header, fn _, charset, encoding, content ->
      decode_content(content, charset, encoding)
    end)
  end

  defp decode_content(content, charset, "Q") do
    content
    |> String.replace("_", " ")
    |> String.replace(~r/=([0-9A-F]{2})/i, fn _, hex -> <<String.to_integer(hex, 16)>> end)
    |> try_convert_to_utf8(charset)
  end

  defp decode_content(content, charset, "B") do
    case Base.decode64(content) do
      {:ok, decoded} -> try_convert_to_utf8(decoded, charset)
      :error -> Logger.error("Failed to decode Base64 MIME header."); ""
    end
  end

  @doc """
  Essaie de convertir une chaîne de caractères du charset spécifié vers UTF-8.
  """
  def try_convert_to_utf8(string, charset) do
    charset_atom = String.to_existing_atom(String.downcase(charset))

    case :unicode.characters_to_binary(string, charset_atom, :utf8) do
      {:ok, binary} -> binary
      :error -> Logger.error("Failed to convert to UTF-8.")
      _ -> sanitize_string(string)
    end
  rescue
    e in ArgumentError ->
      Logger.error("Failed to convert to UTF-8: #{Exception.message(e)}")
      sanitize_string(string)
  end

  @doc """
  Essaie de convertir une chaîne de caractères depuis latin1 vers UTF-8.
  """
  def try_convert_from_latin1(string) do
    case :unicode.characters_to_binary(string, :latin1, :utf8) do
      result when is_binary(result) -> result
      _ -> sanitize_string(string)
    end
  rescue
    _ -> sanitize_string(string)
  end

  @doc """
  Sanitise une chaîne pour s'assurer qu'elle est en UTF-8 valide.
  """
  def sanitize_string(nil), do: nil
  def sanitize_string(str) when is_binary(str) do
    if String.valid?(str), do: str, else: filter_invalid_utf8(str)
  end

  defp filter_invalid_utf8(str) do
    str
    |> String.codepoints()
    |> Enum.filter(&String.valid?/1)
    |> Enum.join("")
  end

  @doc """
  Converts a binary body to a UTF-8 string.
  """
  def convert_body_to_utf8(body) do
    case body do
      body when is_binary(body) ->
        sanitize_string(body)
      body when is_list(body) ->
        List.to_string(body) |> sanitize_string()
      _ ->
        "[Unsupported body format]"
    end
  end

  def sanitize_list(list) when is_list(list), do: Enum.map(list, &sanitize_value/1)
  def sanitize_map(map) when is_map(map), do: Enum.into(map, %{}, fn {k, v} -> {k, sanitize_value(v)} end)

  defp sanitize_value(value) when is_binary(value), do: sanitize_string(value)
  defp sanitize_value(value) when is_map(value), do: sanitize_map(value)
  defp sanitize_value(value) when is_list(value), do: sanitize_list(value)
  defp sanitize_value(value), do: value

  @doc """
  Détermine le type d'une variable pour faciliter le débogage.
  """
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
