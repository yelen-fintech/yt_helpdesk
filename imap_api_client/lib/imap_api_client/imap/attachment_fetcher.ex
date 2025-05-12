defmodule ImapApiClient.Imap.AttachmentFetcher do
  @moduledoc """
  Module spécialisé pour récupérer explicitement les pièces jointes via IMAP
  """

  require Logger

  @doc """
  Récupère explicitement les pièces jointes pour un message donné via IMAP.

  Cette fonction nécessite la bibliothèque IMAP sous-jacente et l'ID du message.
  Elle est conçue pour fonctionner avec différentes implémentations IMAP.

  ## Paramètres

  * `imap_client` - Le client IMAP (ou nom de client) à utiliser
  * `message_id` - L'ID du message dont on veut récupérer les pièces jointes
  * `opts` - Options supplémentaires (facultatif)

  ## Options

  * `:mailbox` - La boîte mail à utiliser (par défaut "INBOX")
  * `:save_dir` - Le répertoire où sauvegarder les pièces jointes (par défaut "attachments")

  ## Retour

  * `{:ok, attachments}` - Une liste des pièces jointes sauvegardées
  * `{:error, reason}` - En cas d'erreur
  """
  def fetch_attachments(imap_client, message_id, opts \\ []) do
    mailbox = Keyword.get(opts, :mailbox, "INBOX")
    save_dir = Keyword.get(opts, :save_dir, "attachments")

    # Créer le répertoire de sauvegarde si nécessaire
    File.mkdir_p!(save_dir)

    Logger.info("Récupération des pièces jointes pour le message #{message_id}...")

    # Tenter d'identifier le type de client IMAP
    case identify_imap_client(imap_client) do
      {:erlmail, _client} ->
        fetch_attachments_erlmail(imap_client, message_id, mailbox, save_dir)

      {:imap_client, _client} ->
        fetch_attachments_imap_client(imap_client, message_id, mailbox, save_dir)

      {:mailex, _client} ->
        fetch_attachments_mailex(imap_client, message_id, mailbox, save_dir)

      {:gen_smtp, _client} ->
        fetch_attachments_gen_smtp(imap_client, message_id, mailbox, save_dir)

      {:pop_mail, _client} ->
        fetch_attachments_pop_mail(imap_client, message_id, mailbox, save_dir)

      _ ->
        # Essayer avec une approche générique
        fetch_attachments_generic(imap_client, message_id, mailbox, save_dir)
    end
  end

  # Identifie le type de client IMAP utilisé
  defp identify_imap_client(client) when is_atom(client) do
    # Si le client est un atome, c'est probablement un nom de client ou un module
    cond do
      Code.ensure_loaded?(:"#{client}.Client") -> {:imap_client, client}
      Code.ensure_loaded?(:"#{client}.IMAP") -> {:erlmail, client}
      Code.ensure_loaded?(:"#{client}.Mailer") -> {:mailex, client}
      Code.ensure_loaded?(:"#{client}.SMTP") -> {:gen_smtp, client}
      Code.ensure_loaded?(:"#{client}.POP3") -> {:pop_mail, client}
      true -> {:unknown, client}
    end
  end

  defp identify_imap_client(client) do
    # Pour un client qui est une structure ou un PID
    cond do
      is_pid(client) -> {:process, client}
      is_map(client) -> identify_imap_client_by_struct(client)
      true -> {:unknown, client}
    end
  end

  defp identify_imap_client_by_struct(%{__struct__: module} = client) do
    module_name = Atom.to_string(module)

    cond do
      String.contains?(module_name, "Imap") -> {:imap_client, client}
      String.contains?(module_name, "Mail") -> {:mailex, client}
      String.contains?(module_name, "SMTP") -> {:gen_smtp, client}
      String.contains?(module_name, "POP") -> {:pop_mail, client}
      true -> {:unknown, client}
    end
  end

  defp identify_imap_client_by_struct(client), do: {:unknown, client}

  # Implémentation pour une bibliothèque IMAP générique
  defp fetch_attachments_generic(client, message_id, mailbox, save_dir) do
    Logger.info("Tentative de récupération avec l'approche générique...")

    try do
      # Essayer plusieurs approches communes dans les bibliothèques IMAP

      # Approche 1: fetch_structure + fetch_body_part
      with {:error, _} <- try_fetch_with_structure(client, message_id, mailbox, save_dir),
           # Approche 2: fetch_parts
           {:error, _} <- try_fetch_with_parts(client, message_id, mailbox, save_dir),
           # Approche 3: fetch_raw + parser
           {:error, _} <- try_fetch_with_raw(client, message_id, mailbox, save_dir) do

        # Dernier recours: fetch_raw et sauvegarder comme .eml
        Logger.warn("Toutes les approches ont échoué, sauvegarde du message brut...")
        save_raw_email(client, message_id, mailbox, save_dir)
      end
    rescue
      e ->
        Logger.error("Erreur lors de la récupération des pièces jointes: #{inspect(e)}")
        {:error, "Exception: #{inspect(e)}"}
    end
  end

  # Essaie d'utiliser la structure MIME pour récupérer les pièces jointes
  defp try_fetch_with_structure(client, message_id, mailbox, save_dir) do
    Logger.info("Tentative avec fetch_structure...")

    # Tenter d'appeler fetch_structure si disponible
    structure_result = try_call_function(client, :fetch_structure, [message_id, mailbox])

    case structure_result do
      {:ok, structure} ->
        # Analyser la structure pour trouver les pièces jointes
        attachment_parts = find_attachment_parts_in_structure(structure)

        if attachment_parts != [] do
          results = Enum.map(attachment_parts, fn part_info ->
            {part_number, filename} = part_info

            # Tenter de récupérer cette partie
            case try_call_function(client, :fetch_body_part, [message_id, part_number, mailbox]) do
              {:ok, content} ->
                path = Path.join(save_dir, filename)
                :ok = File.write!(path, content)
                Logger.info("Pièce jointe sauvegardée: #{filename} -> #{path}")
                {:ok, %{filename: filename, path: path}}

              error ->
                Logger.warn("Échec de récupération de la pièce jointe #{filename}: #{inspect(error)}")
                {:error, "Échec de récupération de la partie #{part_number}"}
            end
          end)

          successes = Enum.filter(results, fn
            {:ok, _} -> true
            _ -> false
          end)

          if successes != [] do
            {:ok, Enum.map(successes, fn {:ok, info} -> info end)}
          else
            {:error, "Aucune pièce jointe n'a pu être récupérée"}
          end
        else
          {:error, "Aucune pièce jointe trouvée dans la structure"}
        end

      _ ->
        {:error, "Échec de récupération de la structure"}
    end
  end

  # Tente de récupérer les parties explicitement
  defp try_fetch_with_parts(client, message_id, mailbox, save_dir) do
    Logger.info("Tentative avec fetch_parts...")

    # Tenter d'appeler fetch_parts si disponible
    parts_result = try_call_function(client, :fetch_parts, [message_id, mailbox])

    case parts_result do
      {:ok, parts} when is_list(parts) ->
        # Filtrer les parties qui sont des pièces jointes
        attachment_parts = Enum.filter(parts, fn part ->
          is_attachment_part?(part)
        end)

        if attachment_parts != [] do
          results = Enum.map(attachment_parts, fn part ->
            filename = get_filename_from_part(part)
            content = get_content_from_part(part)

            if filename && content do
              path = Path.join(save_dir, filename)
              :ok = File.write!(path, content)
              Logger.info("Pièce jointe sauvegardée: #{filename} -> #{path}")
              {:ok, %{filename: filename, path: path}}
            else
              {:error, "Impossible d'extraire le nom ou le contenu de la pièce jointe"}
            end
          end)

          successes = Enum.filter(results, fn
            {:ok, _} -> true
            _ -> false
          end)

          if successes != [] do
            {:ok, Enum.map(successes, fn {:ok, info} -> info end)}
          else
            {:error, "Aucune pièce jointe n'a pu être récupérée"}
          end
        else
          {:error, "Aucune pièce jointe trouvée dans les parties"}
        end

      _ ->
        {:error, "Échec de récupération des parties"}
    end
  end

  # Tente de récupérer le message brut et de le parser
  defp try_fetch_with_raw(client, message_id, mailbox, save_dir) do
    Logger.info("Tentative avec fetch_raw...")

    # Tenter d'appeler fetch_raw si disponible
    raw_result = try_call_function(client, :fetch_raw, [message_id, mailbox])

    case raw_result do
      {:ok, raw_email} when is_binary(raw_email) ->
        # Tenter de parser le message brut
        try do
          # Cette fonction dépend de l'implémentation exacte
          # Nous essayons plusieurs approches communes
          attachments = extract_attachments_from_raw(raw_email)

          if attachments != [] do
            results = Enum.map(attachments, fn {filename, content} ->
              path = Path.join(save_dir, filename)
              :ok = File.write!(path, content)
              Logger.info("Pièce jointe sauvegardée: #{filename} -> #{path}")
              {:ok, %{filename: filename, path: path}}
            end)

            {:ok, Enum.map(results, fn {:ok, info} -> info end)}
          else
            {:error, "Aucune pièce jointe extraite du message brut"}
          end
        rescue
          e ->
            Logger.error("Erreur lors du parsing du message brut: #{inspect(e)}")
            {:error, "Erreur de parsing: #{inspect(e)}"}
        end

      _ ->
        {:error, "Échec de récupération du message brut"}
    end
  end

  # Sauvegarde le message brut comme dernier recours
  defp save_raw_email(client, message_id, mailbox, save_dir) do
    raw_result = try_call_function(client, :fetch_raw, [message_id, mailbox])

    case raw_result do
      {:ok, raw_email} when is_binary(raw_email) ->
        # Sauvegarder comme fichier .eml
        eml_path = Path.join(save_dir, "message_#{message_id}.eml")
        :ok = File.write!(eml_path, raw_email)
        Logger.info("Message brut sauvegardé: #{eml_path}")

        # Créer aussi un fichier texte avec des instructions
        instructions_path = Path.join(save_dir, "instructions_message_#{message_id}.txt")
        instructions = """
        Ce fichier .eml contient un message avec potentiellement des pièces jointes.

        Pour extraire les pièces jointes:
        1. Renommez le fichier avec l'extension .eml s'il n'est pas déjà ainsi
        2. Ouvrez-le avec un client de messagerie comme Thunderbird ou Outlook
        3. Vous pourrez alors voir et extraire les pièces jointes

        Alternativement, utilisez un outil en ligne pour extraire les pièces jointes des fichiers .eml
        """

        :ok = File.write!(instructions_path, instructions)

        {:ok, [%{filename: "message_#{message_id}.eml", path: eml_path, raw: true}]}

      _ ->
        {:error, "Impossible de récupérer le message brut"}
    end
  end

  # Implémentations spécifiques pour différentes bibliothèques

  # Pour les clients utilisant la bibliothèque erlmail
  defp fetch_attachments_erlmail(client, message_id, mailbox, save_dir) do
    Logger.info("Utilisation de l'implémentation erlmail...")

    # Tenter d'obtenir la connexion IMAP
    imap_conn = try_get_imap_connection(client)

    if imap_conn do
      # Sélectionner la boîte mail
      :ok = try_call_function(imap_conn, :select, [mailbox])

      # Récupérer le message
      {:ok, email} = try_call_function(imap_conn, :fetch, [message_id, "RFC822"])

      # Parser le message
      {:ok, parsed} = try_call_function(:erlmail_mime, :parse, [email])

      # Extraire les pièces jointes
      attachments = extract_attachments_erlmail(parsed)

      if attachments != [] do
        results = Enum.map(attachments, fn {filename, content} ->
          path = Path.join(save_dir, filename)
          :ok = File.write!(path, content)
          Logger.info("Pièce jointe sauvegardée: #{filename} -> #{path}")
          %{filename: filename, path: path}
        end)

        {:ok, results}
      else
        # Fallback: sauvegarder en .eml
        eml_path = Path.join(save_dir, "message_#{message_id}.eml")
        :ok = File.write!(eml_path, email)
        Logger.info("Message brut sauvegardé: #{eml_path}")

        {:ok, [%{filename: "message_#{message_id}.eml", path: eml_path, raw: true}]}
      end
    else
      {:error, "Impossible d'obtenir une connexion IMAP"}
    end
  end

  # Pour les clients utilisant la bibliothèque imap_client
  defp fetch_attachments_imap_client(client, message_id, mailbox, save_dir) do
    Logger.info("Utilisation de l'implémentation imap_client...")

    # Sélectionner la boîte mail
    :ok = try_call_function(client, :select, [mailbox])

    # Récupérer le message avec la structure MIME
    {:ok, email} = try_call_function(client, :fetch, [message_id, ["BODYSTRUCTURE", "BODY[]"]])

    # Extraire les pièces jointes à partir de la structure
    structure = Map.get(email, :bodystructure)

    if structure do
      attachment_parts = find_attachment_parts(structure)

      if attachment_parts != [] do
        results = Enum.map(attachment_parts, fn {part_id, filename} ->
          # Récupérer le contenu de la partie
          {:ok, part_content} = try_call_function(client, :fetch, [message_id, {:"BODY[]", part_id}])

          path = Path.join(save_dir, filename)
          :ok = File.write!(path, part_content)
          Logger.info("Pièce jointe sauvegardée: #{filename} -> #{path}")
          %{filename: filename, path: path}
        end)

        {:ok, results}
      else
        # Tenter d'extraire directement du corps complet
        full_body = Map.get(email, :body)
        attachments = extract_attachments_from_raw(full_body)

        if attachments != [] do
          results = Enum.map(attachments, fn {filename, content} ->
            path = Path.join(save_dir, filename)
            :ok = File.write!(path, content)
            Logger.info("Pièce jointe sauvegardée: #{filename} -> #{path}")
            %{filename: filename, path: path}
          end)

          {:ok, results}
        else
          # Fallback: sauvegarder en .eml
          eml_path = Path.join(save_dir, "message_#{message_id}.eml")
          :ok = File.write!(eml_path, full_body)
          Logger.info("Message brut sauvegardé: #{eml_path}")

          {:ok, [%{filename: "message_#{message_id}.eml", path: eml_path, raw: true}]}
        end
      end
    else
      # Fallback si pas de structure: sauvegarder le message brut
      full_body = Map.get(email, :body)
      eml_path = Path.join(save_dir, "message_#{message_id}.eml")
      :ok = File.write!(eml_path, full_body)
      Logger.info("Message brut sauvegardé: #{eml_path}")

      {:ok, [%{filename: "message_#{message_id}.eml", path: eml_path, raw: true}]}
    end
  end

  # Implémentations pour d'autres bibliothèques (simplifiées pour l'exemple)
  defp fetch_attachments_mailex(client, message_id, mailbox, save_dir) do
    # Utiliser l'approche générique pour mailex
    fetch_attachments_generic(client, message_id, mailbox, save_dir)
  end

  defp fetch_attachments_gen_smtp(client, message_id, mailbox, save_dir) do
    # Utiliser l'approche générique pour gen_smtp
    fetch_attachments_generic(client, message_id, mailbox, save_dir)
  end

  defp fetch_attachments_pop_mail(client, message_id, mailbox, save_dir) do
    # Utiliser l'approche générique pour pop_mail
    fetch_attachments_generic(client, message_id, mailbox, save_dir)
  end

  # Fonctions utilitaires

  # Tente d'appeler une fonction sur un module/objet de manière sécurisée
  defp try_call_function(module_or_obj, function, args) when is_atom(module_or_obj) and is_atom(function) do
    if Code.ensure_loaded?(module_or_obj) and function_exported?(module_or_obj, function, length(args)) do
      try do
        result = apply(module_or_obj, function, args)
        {:ok, result}
      rescue
        e -> {:error, "Exception lors de l'appel à #{module_or_obj}.#{function}/#{length(args)}: #{inspect(e)}"}
      end
    else
      {:error, "Fonction #{module_or_obj}.#{function}/#{length(args)} non disponible"}
    end
  end

  defp try_call_function(obj, function, args) when is_map(obj) and is_atom(function) do
    # Pour les objets (structs)
    if Map.has_key?(obj, :__struct__) do
      module = obj.__struct__

      if Code.ensure_loaded?(module) and function_exported?(module, function, length(args) + 1) do
        try do
          result = apply(module, function, [obj | args])
          {:ok, result}
        rescue
          e -> {:error, "Exception lors de l'appel à #{module}.#{function}/#{length(args) + 1}: #{inspect(e)}"}
        end
      else
        {:error, "Fonction #{module}.#{function}/#{length(args) + 1} non disponible"}
      end
    else
      {:error, "Objet non valide"}
    end
  end

  defp try_call_function(pid, function, args) when is_pid(pid) and is_atom(function) do
    # Pour les processus
    try do
      result = :gen_server.call(pid, {function, args})
      {:ok, result}
    rescue
      e -> {:error, "Exception lors de l'appel au processus pour #{function}: #{inspect(e)}"}
    catch
      :exit, reason -> {:error, "Échec de l'appel au processus: #{inspect(reason)}"}
    end
  end

  defp try_call_function(_, _, _), do: {:error, "Argument invalide pour try_call_function"}

  # Essaie de récupérer une connexion IMAP à partir d'un client
  defp try_get_imap_connection(client) do
    # Tenter différentes approches pour obtenir la connexion
    cond do
      is_pid(client) ->
        client

      is_map(client) and Map.has_key?(client, :connection) ->
        Map.get(client, :connection)

      is_map(client) and Map.has_key?(client, :pid) ->
        Map.get(client, :pid)

      is_atom(client) ->
        # Peut-être un nom de processus ou un module
        try do
          case :erlang.whereis(client) do
            pid when is_pid(pid) -> pid
            _ -> nil
          end
        rescue
          _ -> nil
        end

      true -> nil
    end
  end

  # Analyse la structure pour trouver les parties qui sont des pièces jointes
  defp find_attachment_parts_in_structure(structure) do
    # Cette fonction dépend du format exact de la structure MIME
    # Voici une implémentation générique

    find_parts_recursive(structure, "", [])
  end

  defp find_parts_recursive(part, part_path, acc) when is_map(part) do
    # Vérifier si cette partie est une pièce jointe
    is_attachment = cond do
      Map.has_key?(part, :disposition) and
      (part.disposition == "attachment" or part.disposition == "inline") ->
        true

      Map.has_key?(part, :content_disposition) and
      (part.content_disposition =~ "attachment" or part.content_disposition =~ "inline") ->
        true

      Map.has_key?(part, :content_type) and
      not (part.content_type =~ "text/plain" or part.content_type =~ "text/html") ->
        true

      true -> false
    end

    # Récupérer le nom de fichier s'il existe
    filename = cond do
      Map.has_key?(part, :filename) and part.filename != nil ->
        part.filename

      Map.has_key?(part, :name) and part.name != nil ->
        part.name

      is_attachment ->
        # Générer un nom basé sur le type MIME
        content_type = Map.get(part, :content_type, "application/octet-stream")
        ext = content_type |> String.split("/") |> List.last()
        "attachment_#{part_path}_#{:rand.uniform(10000)}.#{ext}"

      true -> nil
    end

    # Ajouter cette partie si c'est une pièce jointe
    new_acc = if is_attachment and filename != nil do
      [{part_path, filename} | acc]
    else
      acc
    end

    # Récursivement chercher dans les sous-parties
    if Map.has_key?(part, :parts) and is_list(part.parts) do
      Enum.with_index(part.parts, fn sub_part, index ->
        new_path = if part_path == "", do: "#{index + 1}", else: "#{part_path}.#{index + 1}"
        find_parts_recursive(sub_part, new_path, new_acc)
      end)
      |> List.flatten()
    else
      new_acc
    end
  end

  defp find_parts_recursive(parts, part_path, acc) when is_list(parts) do
    # Pour une liste de parties
    Enum.with_index(parts, fn part, index ->
      new_path = if part_path == "", do: "#{index + 1}", else: "#{part_path}.#{index + 1}"
      find_parts_recursive(part, new_path, acc)
    end)
    |> List.flatten()
  end

  defp find_parts_recursive(_, _, acc), do: acc

  # Détermine si une partie est une pièce jointe
  defp is_attachment_part?(part) do
    cond do
      is_map(part) ->
        # Vérifier les indices communs pour les pièces jointes
        disposition = Map.get(part, :disposition, "") || Map.get(part, :content_disposition, "")
        content_type = Map.get(part, :content_type, "") || Map.get(part, :type, "")

        (disposition =~ "attachment" or disposition =~ "inline") or
        (content_type != "" and not (content_type =~ "text/plain" or content_type =~ "text/html"))

      is_tuple(part) and tuple_size(part) >= 2 ->
        # Format {content_type, headers, content}
        content_type = elem(part, 0)
        headers = elem(part, 1)

        content_type != "text/plain" and content_type != "text/html" and
        (is_map(headers) and
         (Map.get(headers, "Content-Disposition", "") =~ "attachment" or
          Map.get(headers, "Content-Disposition", "") =~ "inline"))

      true -> false
    end
  end

  # Extrait le nom de fichier d'une partie
  defp get_filename_from_part(part) when is_map(part) do
    cond do
      Map.has_key?(part, :filename) and part.filename != nil ->
        part.filename

      Map.has_key?(part, :name) and part.name != nil ->
        part.name

      Map.has_key?(part, :headers) and is_map(part.headers) ->
        cd = Map.get(part.headers, "Content-Disposition", "") || Map.get(part.headers, "content-disposition", "")

        case Regex.run(~r/filename=[\"\'](.*?)[\"\']/, cd) do
          [_, name] -> name
          _ ->
            # Générer un nom basé sur le type MIME
            content_type = Map.get(part, :content_type, "application/octet-stream")
            ext = content_type |> String.split("/") |> List.last()
            "attachment_#{:rand.uniform(10000)}.#{ext}"
        end

      true ->
        # Générer un nom basé sur le type MIME
        content_type = Map.get(part, :content_type, "application/octet-stream")
        ext = content_type |> String.split("/") |> List.last()
        "attachment_#{:rand.uniform(10000)}.#{ext}"
    end
  end

  defp get_filename_from_part({content_type, headers, _}) when is_map(headers) do
    cd = Map.get(headers, "Content-Disposition", "") || Map.get(headers, "content-disposition", "")

    case Regex.run(~r/filename=[\"\'](.*?)[\"\']/, cd) do
      [_, name] -> name
      _ ->
        # Générer un nom basé sur le type MIME
        ext = content_type |> String.split("/") |> List.last()
        "attachment_#{:rand.uniform(10000)}.#{ext}"
    end
  end

  defp get_filename_from_part(_) do
    "attachment_#{:rand.uniform(10000)}"
  end

  # Extrait le contenu d'une partie
  defp get_content_from_part(part) when is_map(part) do
    cond do
      Map.has_key?(part, :content) and is_binary(part.content) ->
        part.content

      Map.has_key?(part, :data) and is_binary(part.data) ->
        part.data

      Map.has_key?(part, :body) and is_binary(part.body) ->
        part.body

      true -> nil
    end
  end

  defp get_content_from_part({_, _, content}) when is_binary(content) do
    content
  end

  defp get_content_from_part(_) do
    nil
  end

  # Tente d'extraire les pièces jointes d'un message brut
  defp extract_attachments_from_raw(raw_email) when is_binary(raw_email) do
    # Cette fonction est une approximation simplifiée
    # Un vrai parser MIME serait nécessaire pour une solution robuste

    # Trouver les limites des parties MIME
    boundary_match = Regex.run(~r/boundary=\"?([^\"\r\n]+)\"?/, raw_email)

    if boundary_match do
      [_, boundary] = boundary_match

      # Découper en parties MIME
      parts = String.split(raw_email, "--#{boundary}")

      # Chercher les pièces jointes
      Enum.reduce(parts, [], fn part, acc ->
        # Vérifier si c'est une pièce jointe
        cond do
          part =~ ~r/Content-Disposition: attachment|Content-Disposition: inline/ ->
            # Extraire le nom de fichier
            filename_match = Regex.run(~r/filename=\"?([^\";\r\n]+)\"?/, part)

            if filename_match do
              [_, filename] = filename_match

              # Séparer les headers du contenu
              [_, content] = Regex.split(~r/\r?\n\r?\n/, part, parts: 2)

              # Enlever la fin potentielle
              content = String.replace(content, ~r/\r?\n--/, "")

              [{filename, content} | acc]
            else
              acc
            end

          true -> acc
        end
      end)
    else
      []
    end
  end

  defp extract_attachments_from_raw(_), do: []

  # Extrait les pièces jointes pour erlmail
  defp extract_attachments_erlmail(parsed) do
    # Cette fonction est spécifique à la structure erlmail
    # et devrait être adaptée selon la documentation de cette bibliothèque
    []
  end

  # Trouve les parties d'attachement dans une structure MIME
  defp find_attachment_parts(structure) do
    # Implémenter selon le format spécifique de la structure
    []
  end
end
