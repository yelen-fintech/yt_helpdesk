defmodule ImapApiClient.Imap.DebugHandler do
  @moduledoc """
  Module pour déboguer la structure des emails et des pièces jointes
  """

  require Logger

  @doc """
  Analyse en profondeur un message pour comprendre sa structure complète.
  """
  def debug_message_structure(message) do
    IO.puts("\n===== DÉBOGAGE COMPLET DE LA STRUCTURE DU MESSAGE =====")

    # Enregistrer toute la structure dans un fichier pour analyse
    debug_file = "debug_message_#{DateTime.utc_now() |> DateTime.to_unix()}.txt"
    File.write!(debug_file, inspect(message, pretty: true, limit: :infinity))
    IO.puts("Structure complète du message enregistrée dans: #{debug_file}")

    # Afficher les clés principales du message
    IO.puts("\nClés disponibles dans le message:")
    message
    |> Map.keys()
    |> Enum.sort()
    |> Enum.each(fn key -> IO.puts("  - #{inspect(key)}") end)

    # Analyse détaillée du corps du message
    IO.puts("\nAnalyse du corps du message:")
    debug_body_structure(message.body)

    # Recherche des pièces jointes potentielles
    IO.puts("\nRecherche de pièces jointes potentielles:")
    debug_find_attachments(message)

    message
  end

  @doc """
  Analyse la structure du corps du message, qui peut contenir des pièces jointes.
  """
  def debug_body_structure(body) when is_list(body) do
    IO.puts("  Le corps est une liste de #{length(body)} partie(s)")

    Enum.with_index(body, fn part, index ->
      IO.puts("\n  -- Partie #{index + 1} --")
      case part do
        {content_type, headers, content} ->
          IO.puts("    Type: #{content_type}")
          IO.puts("    Headers: #{inspect(headers, pretty: true)}")

          # Afficher un aperçu du contenu selon son type
          content_preview = cond do
            is_binary(content) and byte_size(content) > 200 ->
              "#{inspect(binary_part(content, 0, 200))}... (#{byte_size(content)} bytes)"
            true ->
              inspect(content)
          end

          IO.puts("    Contenu (aperçu): #{content_preview}")

          # Vérifier si cette partie pourrait être une pièce jointe
          cond do
            content_type != "text/plain" and content_type != "text/html" ->
              IO.puts("    => Potentielle pièce jointe détectée (MIME: #{content_type})")

              # Tenter d'extraire un nom de fichier
              filename = case Regex.run(~r/filename=[\"\'](.*?)[\"\']/, Map.get(headers, "Content-Disposition", "")) do
                [_, name] ->
                  IO.puts("    => Nom de fichier trouvé: #{name}")
                  name
                _ ->
                  IO.puts("    => Pas de nom de fichier trouvé dans Content-Disposition")
                  nil
              end

            true -> :ok
          end

        other ->
          IO.puts("    Format inattendu: #{inspect(other)}")
      end
    end)
  end

  def debug_body_structure(body) do
    IO.puts("  Le corps n'est pas une liste: #{inspect(body)}")
  end

  @doc """
  Recherche des pièces jointes dans différentes parties du message.
  """
  def debug_find_attachments(message) do
    # 1. Vérifier la clé :attachments classique
    case Map.get(message, :attachments) do
      nil ->
        IO.puts("  Pas de clé :attachments trouvée")

      attachments when is_map(attachments) and map_size(attachments) == 0 ->
        IO.puts("  La clé :attachments existe mais est une map vide")

      attachments when is_map(attachments) ->
        IO.puts("  La clé :attachments existe et contient #{map_size(attachments)} élément(s):")
        Enum.each(attachments, fn {filename, data} ->
          IO.puts("    - #{filename} (#{byte_size(data)} bytes)")
        end)

      attachments when is_list(attachments) and attachments == [] ->
        IO.puts("  La clé :attachments existe mais est une liste vide")

      attachments when is_list(attachments) ->
        IO.puts("  La clé :attachments existe et contient #{length(attachments)} élément(s):")
        Enum.each(attachments, fn attachment ->
          IO.puts("    - #{inspect(attachment)}")
        end)

      attachments ->
        IO.puts("  La clé :attachments existe avec un format inattendu: #{inspect(attachments)}")
    end

    # 2. Chercher dans d'autres clés potentielles
    potential_attachment_keys = [:attachment, :files, :file, :parts]

    Enum.each(potential_attachment_keys, fn key ->
      if Map.has_key?(message, key) do
        IO.puts("  Clé potentielle pour pièces jointes trouvée: #{key}")
        IO.puts("  Contenu: #{inspect(Map.get(message, key))}")
      end
    end)
  end

  @doc """
  Tente de sauvegarder une pièce jointe en utilisant tous les moyens possibles.
  """
  def force_save_attachments(message) do
    IO.puts("\n===== TENTATIVE FORCÉE D'EXTRACTION DE PIÈCES JOINTES =====")

    # Créer le répertoire si nécessaire
    attachments_dir = "attachments_debug"
    File.mkdir_p!(attachments_dir)

    # 1. Parcourir le corps pour trouver des contenus non-texte
    if is_list(message.body) do
      Enum.with_index(message.body, fn part, index ->
        case part do
          {content_type, headers, content} when content_type != "text/plain" and content_type != "text/html" ->
            # Déterminer un nom de fichier
            filename = case Regex.run(~r/filename=[\"\'](.*?)[\"\']/, Map.get(headers, "Content-Disposition", "")) do
              [_, name] -> name
              _ ->
                ext = content_type |> String.split("/") |> List.last()
                "unknown_part_#{index}.#{ext}"
            end

            path = Path.join(attachments_dir, filename)
            File.write!(path, content)
            IO.puts("  Pièce jointe sauvegardée (depuis le corps): #{filename} -> #{path}")

          _ -> :ok
        end
      end)
    end

    # 2. Essayer via la clé :attachments si elle existe
    case Map.get(message, :attachments) do
      attachments when is_map(attachments) and map_size(attachments) > 0 ->
        Enum.each(attachments, fn {filename, data} ->
          path = Path.join(attachments_dir, filename)
          File.write!(path, data)
          IO.puts("  Pièce jointe sauvegardée (depuis :attachments map): #{filename} -> #{path}")
        end)

      attachments when is_list(attachments) and length(attachments) > 0 ->
        Enum.each(attachments, fn attachment ->
          cond do
            is_map(attachment) and Map.has_key?(attachment, :filename) and Map.has_key?(attachment, :data) ->
              filename = Map.get(attachment, :filename)
              data = Map.get(attachment, :data)
              path = Path.join(attachments_dir, filename)
              File.write!(path, data)
              IO.puts("  Pièce jointe sauvegardée (depuis :attachments liste): #{filename} -> #{path}")

            is_tuple(attachment) and tuple_size(attachment) == 2 ->
              {filename, data} = attachment
              path = Path.join(attachments_dir, filename)
              File.write!(path, data)
              IO.puts("  Pièce jointe sauvegardée (depuis :attachments tuple): #{filename} -> #{path}")

            true -> :ok
          end
        end)

      _ -> :ok
    end

    # 3. Essayer avec d'autres clés potentielles
    potential_attachment_keys = [:attachment, :files, :file, :parts]

    Enum.each(potential_attachment_keys, fn key ->
      if Map.has_key?(message, key) do
        value = Map.get(message, key)

        cond do
          is_binary(value) ->
            path = Path.join(attachments_dir, "unknown_#{key}")
            File.write!(path, value)
            IO.puts("  Contenu binaire sauvegardé (depuis #{key}): #{path}")

          is_map(value) and map_size(value) > 0 ->
            Enum.each(value, fn {k, v} when is_binary(v) ->
              path = Path.join(attachments_dir, "#{key}_#{k}")
              File.write!(path, v)
              IO.puts("  Contenu binaire sauvegardé (depuis #{key}.#{k}): #{path}")

              _ -> :ok
            end)

          is_list(value) ->
            Enum.with_index(value, fn item, idx ->
              if is_binary(item) do
                path = Path.join(attachments_dir, "#{key}_item_#{idx}")
                File.write!(path, item)
                IO.puts("  Contenu binaire sauvegardé (depuis #{key}[#{idx}]): #{path}")
              end
            end)

          true -> :ok
        end
      end
    end)
  end
end
