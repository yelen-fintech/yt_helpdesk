defmodule ImapApiClient.Utils.AttachmentHandler do
  @moduledoc """
  Gère le téléchargement et l'upload vers GitHub des pièces jointes
  présentes dans les emails reçus.
  """

  require Logger
  alias ImapApiClient.Utils.MimeUtils
  alias ImapApiClient.Github.GithubClient

  @doc """
  Traite les pièces jointes d'un message email.
  - Identifie et extrait les pièces jointes
  - Sauvegarde temporairement sur le disque
  - Uploade vers GitHub en lien avec un ticket
  - Supprime les fichiers temporaires

  Arguments:
  - message: Le message email complet
  - issue_number: Le numéro du ticket GitHub associé

  Retourne:
  - {:ok, [attachment_urls]} si réussi avec les URLs des pièces jointes
  - {:error, reason} en cas d'échec
  """
  def process_attachments(message, issue_number) do
    try do
      # Extraire les pièces jointes du message
      attachments = extract_attachments(message)

      if Enum.empty?(attachments) do
        Logger.info("Aucune pièce jointe trouvée dans l'email")
        {:ok, []}
      else
        Logger.info("#{length(attachments)} pièce(s) jointe(s) trouvée(s)")

        # Sauvegarder temporairement et uploader chaque pièce jointe
        results = Enum.map(attachments, fn attachment ->
          with {:ok, temp_path} <- save_attachment_to_temp(attachment),
               {:ok, github_url} <- upload_to_github(temp_path, attachment.filename, issue_number) do

            # Supprimer le fichier temporaire
            File.rm(temp_path)

            # Logger le succès
            Logger.info("Pièce jointe '#{attachment.filename}' uploadée avec succès vers GitHub")
            {:ok, github_url}
          else
            {:error, reason} ->
              Logger.error("Échec du traitement de la pièce jointe '#{attachment.filename}': #{inspect(reason)}")
              {:error, reason}
          end
        end)

        # Filtrer les succès et erreurs
        attachment_urls = results
                          |> Enum.filter(fn result -> match?({:ok, _}, result) end)
                          |> Enum.map(fn {:ok, url} -> url end)

        errors = results
                |> Enum.filter(fn result -> match?({:error, _}, result) end)

        if Enum.empty?(errors) do
          {:ok, attachment_urls}
        else
          Logger.warning("Certaines pièces jointes n'ont pas pu être traitées")
          {:partial, attachment_urls, errors}
        end
      end
    rescue
      e ->
        stacktrace = Exception.format_stacktrace(__STACKTRACE__)
        Logger.error("Erreur lors du traitement des pièces jointes: #{inspect(e)}\n#{stacktrace}")
        {:error, "Traitement des pièces jointes échoué: #{inspect(e)}"}
    end
  end

  @doc """
  Extrait les pièces jointes d'un message email en fonction de sa structure.
  Supporte différents formats d'email et bibliothèques de parsing.
  """
  def extract_attachments(message) do
    cond do
      # Vérifier différentes structures possibles de message pour les pièces jointes
      is_list(get_in_safe(message, [:attachments])) ->
        extract_attachments_from_list(get_in(message, [:attachments]))

      is_list(get_in_safe(message, [:body])) && multipart_message?(message) ->
        extract_attachments_from_multipart(get_in(message, [:body]))

      is_map(get_in_safe(message, [:body])) && has_multiparts?(message) ->
        extract_attachments_from_body_map(get_in(message, [:body]))

      true ->
        []
    end
  end

  # Vérifie si le message est de type multipart
  defp multipart_message?(message) do
    content_type = extract_content_type(message)
    String.contains?(content_type, "multipart")
  end

  # Vérifie si le corps du message contient des parties multiples
  defp has_multiparts?(message) do
    body = get_in_safe(message, [:body])
    is_map(body) && (Map.has_key?(body, :multipart) || Map.has_key?(body, "multipart"))
  end

  # Extrait le Content-Type du message
  defp extract_content_type(message) do
    cond do
      content_type = get_in_safe(message, [:fields, "content-type"]) ->
        to_string(content_type)
      content_type = get_in_safe(message, [:fields, :content_type]) ->
        to_string(content_type)
      content_type = get_in_safe(message, [:headers, "Content-Type"]) ->
        to_string(content_type)
      content_type = get_in_safe(message, [:headers, "content-type"]) ->
        to_string(content_type)
      true ->
        ""
    end
  end

  # Extraction depuis une liste d'attachments explicite
  defp extract_attachments_from_list(attachments) when is_list(attachments) do
    Enum.map(attachments, fn attachment ->
      %{
        filename: safe_get_filename(attachment),
        content: safe_get_content(attachment),
        content_type: safe_get_content_type(attachment)
      }
    end)
  end

  # Extraction depuis un message multipart (format standard MIME)
  defp extract_attachments_from_multipart(parts) when is_list(parts) do
    parts
    |> Enum.filter(fn part ->
      # Identifier les parties qui sont des pièces jointes
      case part do
        {content_type, params, _content} when is_binary(content_type) ->
          has_attachment_disposition?(params) || is_attachment_content_type?(content_type)

        part when is_map(part) ->
          disposition = get_in_safe(part, [:disposition]) || get_in_safe(part, ["disposition"]) || ""
          String.contains?(to_string(disposition), "attachment")

        _ -> false
      end
    end)
    |> Enum.map(fn part ->
      case part do
        {content_type, params, content} when is_binary(content) ->
          filename = extract_filename_from_params(params) || "attachment_#{:erlang.unique_integer([:positive])}"
          %{
            filename: filename,
            content: content,
            content_type: content_type
          }

        part when is_map(part) ->
          %{
            filename: get_in_safe(part, [:filename]) || get_in_safe(part, ["filename"]) || "attachment_#{:erlang.unique_integer([:positive])}",
            content: get_in_safe(part, [:content]) || get_in_safe(part, ["content"]) || "",
            content_type: get_in_safe(part, [:content_type]) || get_in_safe(part, ["content_type"]) || "application/octet-stream"
          }
      end
    end)
  end

  # Extraction depuis une structure de corps complexe
  defp extract_attachments_from_body_map(body) when is_map(body) do
    if get_in_safe(body, [:multipart]) || get_in_safe(body, ["multipart"]) do
      parts = get_in_safe(body, [:parts]) || get_in_safe(body, ["parts"]) || []
      extract_attachments_from_multipart(parts)
    else
      []
    end
  end

  # Vérifie si les paramètres indiquent une pièce jointe
  defp has_attachment_disposition?(params) when is_map(params) do
    disp = Map.get(params, "disposition", "") || Map.get(params, :disposition, "")
    String.contains?(to_string(disp), "attachment")
  end
  defp has_attachment_disposition?(_), do: false

  # Vérifie si le type de contenu correspond à une pièce jointe
  defp is_attachment_content_type?(content_type) do
    content_type = String.downcase(content_type)
    !String.contains?(content_type, "text/plain") &&
    !String.contains?(content_type, "text/html") &&
    !String.starts_with?(content_type, "multipart/")
  end

  # Extrait le nom de fichier depuis les paramètres
  defp extract_filename_from_params(params) when is_map(params) do
    filename = Map.get(params, "filename") || Map.get(params, :filename)
    if filename, do: MimeUtils.decode_mime_header(filename), else: nil
  end
  defp extract_filename_from_params(_), do: nil

  # Accesseurs sécurisés pour différentes structures d'attachement
  defp safe_get_filename(attachment) do
    cond do
      is_map(attachment) && (Map.has_key?(attachment, :filename) || Map.has_key?(attachment, "filename")) ->
        filename = Map.get(attachment, :filename) || Map.get(attachment, "filename")
        MimeUtils.decode_mime_header(filename)
      true ->
        "attachment_#{:erlang.unique_integer([:positive])}"
    end
  end

  defp safe_get_content(attachment) do
    cond do
      is_map(attachment) && (Map.has_key?(attachment, :content) || Map.has_key?(attachment, "content")) ->
        Map.get(attachment, :content) || Map.get(attachment, "content")
      is_map(attachment) && (Map.has_key?(attachment, :body) || Map.has_key?(attachment, "body")) ->
        Map.get(attachment, :body) || Map.get(attachment, "body")
      is_tuple(attachment) && tuple_size(attachment) >= 3 ->
        elem(attachment, 2)
      true ->
        ""
    end
  end

  defp safe_get_content_type(attachment) do
    cond do
      is_map(attachment) && (Map.has_key?(attachment, :content_type) || Map.has_key?(attachment, "content_type")) ->
        Map.get(attachment, :content_type) || Map.get(attachment, "content_type")
      is_tuple(attachment) && tuple_size(attachment) >= 1 ->
        elem(attachment, 0)
      true ->
        "application/octet-stream"
    end
  end

  # Fonction utilitaire pour get_in avec gestion d'erreur
  defp get_in_safe(map, keys) do
    try do
      result = get_in(map, keys)
      if is_nil(result), do: false, else: result
    rescue
      _ -> false
    end
  end

  @doc """
  Sauvegarde une pièce jointe dans un fichier temporaire.
  """
  def save_attachment_to_temp(attachment) do
    try do
      # Sanitize filename pour éviter des caractères non valides dans le chemin
      safe_filename = attachment.filename
                      |> String.replace(~r/[^a-zA-Z0-9_\.\-]/, "_")

      # Créer un nom de fichier temporaire unique
      temp_dir = System.tmp_dir!()
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      unique_id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
      temp_path = Path.join([temp_dir, "#{timestamp}_#{unique_id}_#{safe_filename}"])

      # Écrire le contenu dans le fichier temporaire
      content = attachment.content

      # S'assurer que le contenu est binaire
      binary_content = cond do
        is_binary(content) -> content
        is_list(content) -> List.to_string(content)
        true -> inspect(content)
      end

      :ok = File.write(temp_path, binary_content)

      Logger.debug("Pièce jointe sauvegardée temporairement à: #{temp_path}")
      {:ok, temp_path}
    rescue
      e ->
        Logger.error("Erreur lors de la sauvegarde de la pièce jointe: #{inspect(e)}")
        {:error, "Erreur de sauvegarde: #{inspect(e)}"}
    end
  end

  @doc """
  Upload un fichier vers GitHub et l'attache au ticket indiqué.
  """
  def upload_to_github(file_path, filename, issue_number) do
    try do
      # Lire le contenu du fichier
      {:ok, file_content} = File.read(file_path)

      # Préparer la description du fichier
      description = "Pièce jointe de l'email: #{filename}"

      # Upload vers GitHub en tant qu'asset
      case GithubClient.upload_asset(issue_number, file_path, filename, description) do
        {:ok, response} ->
          # Extraire l'URL de téléchargement depuis la réponse
          download_url = Map.get(response, "browser_download_url") ||
                         Map.get(response, "url") ||
                         "URL indisponible"

          # Ajouter un commentaire au ticket avec le lien
          comment_body = """
          📎 **Pièce jointe téléchargée**

          Nom: `#{filename}`
          [Télécharger le fichier](#{download_url})
          """

          {:ok, _} = GithubClient.add_comment(issue_number, comment_body)

          {:ok, download_url}

        {:error, reason} ->
          Logger.error("Échec de l'upload vers GitHub: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Erreur lors de l'upload vers GitHub: #{inspect(e)}")
        {:error, "Erreur d'upload: #{inspect(e)}"}
    end
  end
end
