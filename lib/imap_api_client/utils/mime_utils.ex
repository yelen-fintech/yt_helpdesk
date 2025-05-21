defmodule ImapApiClient.Utils.MimeUtils do
  @moduledoc """
  Utilitaires pour le traitement des données MIME et l'encodage de caractères.
  Ce module fournit des fonctions pour décoder les en-têtes MIME, sanitiser les 
  chaînes pour garantir un encodage UTF-8 valide, et d'autres fonctions utiles
  pour le traitement des données d'email.
  """
  
  require Logger
  
  @doc """
  Décode les en-têtes MIME encodés.
  
  Gère les formats suivants:
  - =?charset?Q?encoded-text?= (Quoted-Printable)
  - =?charset?B?encoded-text?= (Base64)
  
  Exemples:
    iex> ImapApiClient.Utils.MimeUtils.decode_mime_header("=?UTF-8?Q?Acc=C3=A8s_=C3=A0_mes_comptes?=")
    "Accès à mes comptes"
    
    iex> ImapApiClient.Utils.MimeUtils.decode_mime_header("=?UTF-8?B?QWNjw6hzIMOgIG1lcyBjb21wdGVz?=")
    "Accès à mes comptes"
  """
  def decode_mime_header(header) when is_binary(header) do
    if String.match?(header, ~r/=\?[\w-]+\?[QB]\?.*?\?=/) do
      # Trouver toutes les parties encodées et les remplacer
      Regex.replace(~r/=\?([\w-]+)\?([QB])\?(.*?)\?=/, header, fn whole_match, charset, encoding, content ->
        case encoding do
          "Q" ->
            # Décodage Q-encoding (Quoted-Printable)
            decoded = content
                      |> String.replace("_", " ")  # Underscore en espace dans Q-encoding
                      |> String.replace(~r/=([0-9A-F]{2})/i, fn _, hex -> 
                         <<String.to_integer(hex, 16)>> 
                      end)
            
            # Conversion vers UTF-8
            try_convert_to_utf8(decoded, charset)
            
          "B" ->
            # Décodage Base64
            try do
              decoded = Base.decode64!(content)
              try_convert_to_utf8(decoded, charset)
            rescue
              e ->
                Logger.error("Failed to decode Base64 MIME header: #{Exception.message(e)}")
                whole_match  # Conserver le texte original en cas d'erreur
            end
            
          _ -> whole_match  # Encodage non supporté
        end
      end)
    else
      # Si ce n'est pas un encodage MIME, utiliser la sanitisation normale
      sanitize_string(header)
    end
  end
  def decode_mime_header(nil), do: nil
  def decode_mime_header(other), do: sanitize_string(to_string(other))
  
  @doc """
  Essaie de convertir une chaîne de caractères du charset spécifié vers UTF-8.
  """
  def try_convert_to_utf8(string, charset) do
    charset_atom = String.downcase(charset) |> String.to_atom()
    
    try do
      case :unicode.characters_to_binary(string, charset_atom, :utf8) do
        result when is_binary(result) -> result
        {:error, _, _} -> 
          # Si l'encodage spécifique échoue, essayer avec latin1 comme fallback
          try_convert_from_latin1(string)
        {:incomplete, result, _} -> 
          # Conversion partielle, prendre le résultat et continuer
          sanitize_string(result)
      end
    rescue
      e ->
        Logger.error("Failed to convert string to UTF-8: #{Exception.message(e)}")
        try_convert_from_latin1(string)
    end
  end
  
  @doc """
  Essaie de convertir une chaîne de caractères depuis latin1 (ISO-8859-1) vers UTF-8.
  """
  def try_convert_from_latin1(string) do
    try do
      case :unicode.characters_to_binary(string, :latin1, :utf8) do
        result when is_binary(result) -> result
        _ -> sanitize_string(string)  # Si ça échoue, nettoyer la chaîne
      end
    rescue
      _ -> sanitize_string(string)
    end
  end
  
  @doc """
  Sanitise une chaîne pour s'assurer qu'elle est en UTF-8 valide.
  Filtre les caractères non valides en UTF-8.
  """
  def sanitize_string(nil), do: nil
  def sanitize_string(str) when is_binary(str) do
    if String.valid?(str) do
      str  # Déjà une chaîne UTF-8 valide
    else
      try do
        # Essayer de nettoyer les caractères non-UTF8
        str
        |> String.codepoints()
        |> Enum.filter(fn char -> String.valid?(char) end)
        |> Enum.join("")
      rescue
        _ ->
          # Fallback: traiter comme une liste de bytes et filtrer ceux qui ne sont pas valides en UTF-8
          str
          |> :binary.bin_to_list()
          |> Enum.filter(fn byte -> byte < 128 end)  # Garder seulement les ASCII
          |> List.to_string()
      end
    end
  end
  def sanitize_string(other), do: inspect(other)
  
  @doc """
  Sanitiser une liste récursivement.
  """
  def sanitize_list(list) when is_list(list) do
    Enum.map(list, fn
      item when is_binary(item) -> sanitize_string(item)
      item when is_map(item) -> sanitize_map(item)
      item when is_list(item) -> sanitize_list(item)
      item -> item
    end)
  end
  
  @doc """
  Sanitiser une map récursivement.
  """
  def sanitize_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      sanitized_value = cond do
        is_binary(v) -> sanitize_string(v)
        is_map(v) -> sanitize_map(v)
        is_list(v) -> sanitize_list(v)
        true -> v
      end
      Map.put(acc, k, sanitized_value)
    end)
  end
  def sanitize_map(other), do: other
  
  @doc """
  Convertit un corps de message potentiellement binaire en chaîne UTF-8.
  Gère différents formats de données possibles pour le corps.
  """
  def convert_body_to_utf8(body) do
    cond do
      is_binary(body) -> 
        sanitize_string(body)
      is_list(body) -> 
        List.to_string(body) |> sanitize_string()
      # Gérer le cas spécial des binaires (<<...>>)
      true -> 
        try do
          # Essayer de le convertir en chaîne UTF-8
          if is_binary(body) do
            :unicode.characters_to_binary(body, :latin1, :utf8)
          else
            bin_body = IO.iodata_to_binary(body)
            :unicode.characters_to_binary(bin_body, :latin1, :utf8)
          end
        rescue
          e ->
            Logger.error("Failed to convert body to UTF-8: #{Exception.message(e)}")
            # Fallback: traiter comme une chaîne ASCII
            try do
              if is_binary(body) do
                body
                |> :binary.bin_to_list()
                |> Enum.filter(fn byte -> byte < 128 end)
                |> List.to_string()
              else
                inspect(body)
              end
            rescue
              _ -> "[Content could not be encoded properly]"
            end
        end
    end
  end
  
  @doc """
  Détermine le type d'une variable pour faciliter le débogage.
  """
  def typeof(self) do
    cond do
      is_float(self)    -> "float"
      is_number(self)   -> "number"
      is_atom(self)     -> "atom"
      is_boolean(self)  -> "boolean"
      is_binary(self)   -> "binary"
      is_function(self) -> "function"
      is_list(self)     -> "list"
      is_tuple(self)    -> "tuple"
      is_map(self)      -> "map"
      is_pid(self)      -> "pid"
      is_port(self)     -> "port"
      is_reference(self) -> "reference"
      true              -> "unknown"
    end
  end
end
