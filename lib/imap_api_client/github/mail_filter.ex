defmodule ImapApiClient.Github.MailFilter do
  @moduledoc """
  Filtre et traite les emails pour créer des tickets GitHub appropriés
  en utilisant une classification automatique.
  """

  require Logger
  alias ImapApiClient.Github.GithubClient
  alias ImapApiClient.Utils.MimeUtils

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
      subject = MimeUtils.decode_mime_header(email_info.subject || "[Sans Sujet]")
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
    %{
      from: MimeUtils.decode_mime_header(extract_field(message, "from")),
      to: MimeUtils.decode_mime_header(extract_field(message, "to")),
      date: extract_field(message, "date"),
      subject: extract_field(message, "subject"),
      body: extract_and_decode_body(message)
    }
  end

  # Nouvelle fonction pour extraire et décoder le corps du message
  defp extract_and_decode_body(message) do
    body = extract_body(message)

    # Déterminer l'encodage potentiel du corps
    charset = extract_charset(message) || "utf-8"

    # Convertir en utilisant le bon charset
    case body do
      binary when is_binary(binary) ->
        MimeUtils.convert_body_to_utf8(binary, charset)
      other ->
        MimeUtils.safe_to_string(other)
    end
  end

  # Extraction du charset depuis le message
  defp extract_charset(message) do
    cond do
      # Chercher dans les en-têtes Content-Type ou similaires
      content_type = extract_field(message, "content-type") ->
        extract_charset_from_content_type(content_type)
      # Essayer d'autres champs qui pourraient contenir l'information charset
      get_in_safe(message, [:body, :charset]) ->
        get_in(message, [:body, :charset])
      get_in_safe(message, [:body, "charset"]) ->
        get_in(message, [:body, "charset"])
      get_in_safe(message, [:fields, :content_type, :charset]) ->
        get_in(message, [:fields, :content_type, :charset])
      true ->
        nil
    end
  end

  # Extraction du charset depuis un en-tête Content-Type
  defp extract_charset_from_content_type(content_type) when is_binary(content_type) do
    case Regex.run(~r/charset=["']?([^"';]+)["']?/i, content_type) do
      [_, charset] -> charset
      _ -> nil
    end
  end
  defp extract_charset_from_content_type(_), do: nil

  # Fonctions privées
  defp extract_field(message, field_name) do
    cond do
      is_nil(message) || message == %{} -> ""
      is_list(get_in_safe(message, [:headers])) -> Enum.find_value(message.headers, "", fn {header, value} -> if String.downcase(header) == String.downcase(field_name), do: value, else: nil end)
      get_in_safe(message, [:fields, String.to_atom(field_name)]) -> get_in(message, [:fields, String.to_atom(field_name)])
      get_in_safe(message, [:fields, field_name]) -> get_in(message, [:fields, field_name])
      get_in_safe(message, ["fields", field_name]) -> get_in(message, ["fields", field_name])
      Map.has_key?(message, String.to_atom(field_name)) -> Map.get(message, String.to_atom(field_name))
      Map.has_key?(message, field_name) -> Map.get(message, field_name)
      get_in_safe(message, [:header, field_name]) -> get_in(message, [:header, field_name])
      get_in_safe(message, ["header", field_name]) -> get_in(message, ["header", field_name])
      true -> ""
    end
  end

  defp get_in_safe(map, keys) do
    try do
      result = get_in(map, keys)
      if is_nil(result), do: false, else: result
    rescue
      _ -> false
    end
  end

  defp extract_body(message) do
    cond do
      is_nil(message) -> ""
      is_binary(get_in_safe(message, [:body])) -> get_in(message, [:body])
      is_list(get_in_safe(message, [:body])) -> extract_multipart_body(get_in(message, [:body]))
      get_in_safe(message, [:body, :text]) -> get_in(message, [:body, :text])
      get_in_safe(message, [:body, "text"]) -> get_in(message, [:body, "text"])
      get_in_safe(message, ["body", "text"]) -> get_in(message, ["body", "text"])
      get_in_safe(message, [:body, :html]) -> get_in(message, [:body, :html])
      get_in_safe(message, [:body, "html"]) -> get_in(message, [:body, "html"])
      get_in_safe(message, ["body", "html"]) -> get_in(message, ["body", "html"])
      get_in_safe(message, [:content]) -> extract_content(get_in(message, [:content]))
      get_in_safe(message, ["content"]) -> extract_content(get_in(message, ["content"]))
      true -> try do inspect(message) rescue _ -> "[Contenu non extractible]" end
    end
  end

  defp extract_multipart_body(parts) when is_list(parts) do
    text_part = Enum.find_value(parts, "", fn part ->
      case part do
        {"text/plain", _params, content} when is_binary(content) -> content
        {content_type, _params, content} when is_binary(content) and is_binary(content_type) ->
          if String.contains?(content_type, "text/plain"), do: content, else: nil
        _ -> nil
      end
    end)

    if text_part != "", do: text_part, else: "[Email multipart sans contenu texte]"
  end

  defp extract_multipart_body(_), do: ""

  defp extract_content(content) do
    cond do
      is_binary(content) -> content
      is_map(content) && Map.has_key?(content, :data) -> content.data
      is_map(content) && Map.has_key?(content, "data") -> content["data"]
      true -> ""
    end
  end

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
    from = email_info.from || "[Expéditeur inconnu]"
    date = email_info.date || "[Date inconnue]"
    subject = MimeUtils.decode_mime_header(email_info.subject) || "[Sans sujet]"

    # Le corps a déjà été traité dans extract_and_decode_body
    body = if is_binary(email_info.body), do: email_info.body, else: MimeUtils.safe_to_string(email_info.body)
    body = body || "[Contenu vide]"

    """
    ## Email Information
    **From:** #{from}
    **To:** #{email_info.to}
    **Date:** #{date}
    **Subject:** #{subject}
    **Classification:** #{classification.category}
    **Priority:** #{Map.get(classification, :priority, "medium")}

    ## Email Content
    #{body}
    """
  end

  defp safe_get_issue_number(issue) do
    cond do
      is_map(issue) && Map.has_key?(issue, "number") -> issue["number"]
      is_map(issue) && Map.has_key?(issue, :number) -> issue[:number]
      is_struct(issue) && Map.has_key?(issue, :number) -> issue.number
      is_map(issue) && (Map.has_key?(issue, "html_url") || Map.has_key?(issue, "url")) -> extract_number_from_url(issue)
      true -> "unknown-#{:rand.uniform(1000)}"
    end
  end

  defp extract_number_from_url(issue) do
    url = if Map.has_key?(issue, "html_url"), do: issue["html_url"], else: issue["url"]
    case Regex.run(~r/\/issues\/(\d+)$/, url) do
      [_, number] -> String.to_integer(number)
      _ -> "unknown"
    end
  end
end
