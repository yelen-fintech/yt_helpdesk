defmodule ImapApiClient.Github.MailFilter do
  @moduledoc """
  Filtre et traite les emails pour créer des tickets GitHub appropriés
  en utilisant une classification automatique.
  """

  require Logger
  alias ImapApiClient.Github.GithubClient

  @doc """
  Traite un email reçu avec la classification fournie:
  1. Extrait les infos importantes
  2. Utilise la classification fournie par le modèle de classification
  3. Crée un ticket GitHub avec les labels appropriés

  Retourne {:ok, :issue_created, issue_number} si réussi
  ou {:error, reason} en cas d'échec
  """
  def process_email(message, classification) do
    try do
      # Extraire les informations pertinentes de l'email
      email_info = extract_email_info(message)

      # Log pour déboguer la structure extraite
      Logger.debug("Email en traitement avec classification: #{inspect(classification)}")

      Logger.info("Email classifié comme: #{classification.category} (confiance: #{classification.confidence})")

      # Déterminer les labels et la priorité basés sur la classification
      {labels, priority} = get_labels_and_priority(classification)

      # Créer le ticket GitHub avec fallbacks pour les valeurs potentiellement nil
      subject = email_info.subject || "[Sans Sujet]"
      title = "#{priority}: #{subject}"
      body = format_ticket_body(email_info, classification)

      {:ok, issue} = GithubClient.create_issue(title, body, labels)

      # Extraire le numéro du ticket d'une façon sécurisée
      issue_number = safe_get_issue_number(issue)

      Logger.info("Issue ##{issue_number} created successfully")
      {:ok, :issue_created, issue_number}
    rescue
      e ->
        stacktrace = Exception.format_stacktrace(__STACKTRACE__)
        Logger.error("Erreur lors du traitement de l'email: #{inspect(e)}\n#{stacktrace}")
        {:error, "Traitement de l'email échoué: #{inspect(e)}"}
    end
  end

  @doc """
  Extrait les informations importantes d'un message email
  """
  def extract_email_info(message) do

    # Extraction améliorée avec plus de fallbacks
    %{
      from: extract_field(message, "from"),
      to: extract_field(message, "to"),
      date: extract_field(message, "date"),
      subject: extract_field(message, "subject"),
      body: extract_body(message)
    }
  end

  # Fonctions privées

  # Nouvelle fonction d'extraction générique pour couvrir plus de cas
  defp extract_field(message, field_name) do
    cond do
      # Si message est nil ou vide
      is_nil(message) || message == %{} ->
        ""

      # Si les headers sont présents sous forme de liste de tuples
      is_list(get_in_safe(message, [:headers])) ->
        Enum.find_value(message.headers, "", fn
          {header, value} when is_binary(header) ->
            if String.downcase(header) == String.downcase(field_name), do: value, else: nil
          _ -> nil
        end)

      # Access via .fields atom
      get_in_safe(message, [:fields, String.to_atom(field_name)]) ->
        get_in(message, [:fields, String.to_atom(field_name)])

      # Access via .fields string
      get_in_safe(message, [:fields, field_name]) ->
        get_in(message, [:fields, field_name])

      # Access via ["fields"] string key
      get_in_safe(message, ["fields", field_name]) ->
        get_in(message, ["fields", field_name])

      # Access via direct attribute as atom
      Map.has_key?(message, String.to_atom(field_name)) ->
        Map.get(message, String.to_atom(field_name))

      # Access via direct attribute as string
      Map.has_key?(message, field_name) ->
        Map.get(message, field_name)

      # Essayer d'accéder directement à un champ header
      get_in_safe(message, [:header, field_name]) ->
        get_in(message, [:header, field_name])

      # Essayer d'accéder directement à un champ header
      get_in_safe(message, ["header", field_name]) ->
        get_in(message, ["header", field_name])

      # Si rien ne fonctionne
      true ->
        ""
    end
  end

  # Helper pour éviter les erreurs quand on essaie d'accéder à des champs qui n'existent pas
  defp get_in_safe(map, keys) do
    try do
      result = get_in(map, keys)
      if is_nil(result), do: false, else: result
    rescue
      _ -> false
    end
  end

  # Fonction améliorée pour extraire le corps du message
  defp extract_body(message) do
    cond do
      # Si message est nil
      is_nil(message) ->
        ""

      # Si body est directement une string
      is_binary(get_in_safe(message, [:body])) ->
        get_in(message, [:body])

      # Si body est directement une string avec clé string
      is_binary(get_in_safe(message, ["body"])) ->
        get_in(message, ["body"])

      # Si body est une liste (multi-part)
      is_list(get_in_safe(message, [:body])) ->
        extract_multipart_body(get_in(message, [:body]))

      # Si body est une liste (multi-part) avec clé string
      is_list(get_in_safe(message, ["body"])) ->
        extract_multipart_body(get_in(message, ["body"]))

      # Si body contient un champ :text
      get_in_safe(message, [:body, :text]) ->
        get_in(message, [:body, :text])

      # Si body contient un champ "text"
      get_in_safe(message, [:body, "text"]) ->
        get_in(message, [:body, "text"])

      # Si body contient un champ text (via ["body"])
      get_in_safe(message, ["body", "text"]) ->
        get_in(message, ["body", "text"])

      # Si body contient un champ :html et pas de texte
      get_in_safe(message, [:body, :html]) ->
        get_in(message, [:body, :html])

      # Si body contient un champ "html" (string key)
      get_in_safe(message, [:body, "html"]) ->
        get_in(message, [:body, "html"])

      # Si body contient un champ html (via ["body"])
      get_in_safe(message, ["body", "html"]) ->
        get_in(message, ["body", "html"])

      # Si content est utilisé au lieu de body
      get_in_safe(message, [:content]) ->
        extract_content(get_in(message, [:content]))

      # Si content est utilisé avec clé string
      get_in_safe(message, ["content"]) ->
        extract_content(get_in(message, ["content"]))

      # Si payload ou parts sont utilisés (format Gmail API)
      get_in_safe(message, [:payload, :parts]) ->
        extract_parts(get_in(message, [:payload, :parts]))

      # Si la structure est complètement différente, essayer un dernier fallback
      true ->
        try do
          inspect(message)
        rescue
          _ -> "[Contenu non extractible]"
        end
    end
  end

  # Gestion du cas où body est une liste de parties
  defp extract_multipart_body(parts) when is_list(parts) do
    # Essayer de trouver une partie texte d'abord
    text_part = Enum.find_value(parts, "", fn part ->
      case part do
        {"text/plain", _params, content} when is_binary(content) ->
          content
        {content_type, _params, content} when is_binary(content) and is_binary(content_type) ->
          if String.contains?(content_type, "text/plain"), do: content, else: nil
        _ -> nil
      end
    end)

    if text_part != "", do: text_part, else: "[Email multipart sans contenu texte]"
  end
  defp extract_multipart_body(_), do: ""

  # Extraction depuis le champ content (utilisé par certaines API)
  defp extract_content(content) do
    cond do
      is_binary(content) -> content
      is_map(content) && Map.has_key?(content, :data) -> content.data
      is_map(content) && Map.has_key?(content, "data") -> content["data"]
      true -> ""
    end
  end

  # Extraction depuis parts (format Gmail API)
  defp extract_parts(parts) when is_list(parts) do
    text_part = Enum.find_value(parts, "", fn part ->
      mime_type = Map.get(part, :mimeType, Map.get(part, "mimeType", ""))
      if String.contains?(mime_type, "text/plain") do
        get_in(part, [:body, :data]) || get_in(part, ["body", "data"]) || ""
      else
        nil
      end
    end)

    if text_part != "", do: text_part, else: "[Email sans contenu texte extractible]"
  end
  defp extract_parts(_), do: ""

  defp get_labels_and_priority(classification) do
    # Utiliser la priorité prédite par le modèle s'il en fournit une
    priority_value = Map.get(classification, :priority, "medium")

    # Conversion de priorité en préfixe pour le titre
    priority = case String.downcase(priority_value) do
      "urgent" -> "HIGH"
      "high" -> "HIGH"
      "low" -> "LOW"
      _ -> "MEDIUM"
    end

    # Labels basés sur la catégorie
    labels = case classification.category do
      "spam" -> ["spam"]
      "promotions_marketing" -> ["marketing"]
      "personnel" -> ["personal"]
      "professionnel_interne" -> ["internal"]
      "support_client" -> ["support"]
      "demande_information_question" -> ["question", "info-request"]
      "feedback_suggestion" -> ["feedback", "suggestion"]
      "documentation" -> ["documentation"]
      "account" -> ["account"]
      "payment" -> ["payment"]
      "technical" -> ["bug", "technical"]
      "order" -> ["order"]
      "general" -> ["general"]
      _ -> ["other"]
    end

    # Ajouter les labels supplémentaires fournis par la classification
    additional_labels = Map.get(classification, :labels, [])
    all_labels = labels ++ additional_labels |> Enum.uniq()

    {all_labels, priority}
  end

  defp format_ticket_body(email_info, classification) do
    # Ajout de valeurs par défaut pour s'assurer que tous les champs ont une valeur
    # Conversion du champ from en string si c'est une liste
    from = format_email_field(email_info.from) || "[Expéditeur inconnu]"
    # Conversion de la date en string si c'est une DateTime
    date = format_date_field(email_info.date) || "[Date inconnue]"
    # Formatage du champ to si nécessaire
    to = format_email_field(email_info.to) || "[Destinataire inconnu]"
    subject = email_info.subject || "[Sans sujet]"
    body = email_info.body || "[Contenu vide]"

    """
    ## Email Information
    **From:** #{from}
    **To:** #{to}
    **Date:** #{date}
    **Subject:** #{subject}
    **Classification:** #{classification.category})
    **Priority:** #{Map.get(classification, :priority, "medium")}

    ## Email Content
    #{body}
    """
  end

  # Formatage spécial pour les champs email qui peuvent être des listes de tuples {nom, email}
  defp format_email_field(field) do
    cond do
      is_nil(field) -> nil
      is_binary(field) -> field
      is_list(field) ->
        try do
          # Pour les listes de tuples {nom, email}
          Enum.map_join(field, ", ", fn
            {name, email} ->
              if is_nil(name) || name == "", do: email, else: "#{name} <#{email}>"
            # Suppression de la clause redondante: {nil, email} -> email
            # Pour la structure [nil: "email@example.com"]
            [{key, email}] when is_atom(key) -> email
            # Fallback pour les autres formats de liste
            item when is_binary(item) -> item
            item -> inspect(item)
          end)
        rescue
          _ -> inspect(field)
        end
      true -> inspect(field)
    end
  end

  # Formatage spécial pour les champs de date
  defp format_date_field(date) do
    cond do
      is_nil(date) -> nil
      is_binary(date) -> date
      # Si c'est une DateTime struct (comme ~U[2025-05-13 14:29:23Z])
      match?(%DateTime{}, date) ->
        try do
          Calendar.strftime(date, "%Y-%m-%d %H:%M:%S %Z")
        rescue
          _ -> to_string(date)
        end
      true -> inspect(date)
    end
  end

  defp safe_get_issue_number(issue) do
    cond do
      # Issue sous forme de map avec chaîne
      is_map(issue) && Map.has_key?(issue, "number") ->
        issue["number"]

      # Issue sous forme de map avec atom
      is_map(issue) && Map.has_key?(issue, :number) ->
        issue[:number]

      # Issue sous forme de struct
      is_struct(issue) && Map.has_key?(issue, :number) ->
        issue.number

      # Issue avec URL
      is_map(issue) && (Map.has_key?(issue, "html_url") || Map.has_key?(issue, "url")) ->
        extract_number_from_url(issue)

      # Fallback
      true ->
        "unknown-#{:rand.uniform(1000)}"
    end
  end

  # Essaye d'extraire le numéro d'issue depuis l'URL
  defp extract_number_from_url(issue) do
    cond do
      is_map(issue) && Map.has_key?(issue, "html_url") ->
        url = issue["html_url"]
        case Regex.run(~r/\/issues\/(\d+)$/, url) do
          [_, number] -> String.to_integer(number)
          _ -> "unknown"
        end

      is_map(issue) && Map.has_key?(issue, "url") ->
        url = issue["url"]
        case Regex.run(~r/\/issues\/(\d+)$/, url) do
          [_, number] -> String.to_integer(number)
          _ -> "unknown"
        end

      true ->
        "unknown"
    end
  end
end
