defmodule ImapApiClient.Github.MailFilter do
  @moduledoc """
  Filtre les emails reçus, les classifie via l'API Python et crée des tickets GitHub correspondants
  """

  require Logger
  alias ImapApiClient.Github.GithubClient

  def classification_api_url do
    Application.get_env(:imap_api_client, :github)[:classification_api_url] || "http://localhost:5000/classify"
  end

  @doc """
  Traite un message email en le classifiant et en créant un ticket GitHub
  """
  def process_email(message) do
    body_text = extract_plaintext_body(message.body)
    sender = format_sender(message.sender)

    classification_payload = %{
      subject: message.subject,
      body: body_text
    }

    case classify_email(classification_payload) do
      {:ok, classification} ->
        create_github_issue(message, classification, sender, body_text)

      {:error, reason} ->
        Logger.error("Échec de la classification de l'email: #{reason}")
        {:error, "Classification échouée: #{reason}"}
    end
  end

defp classify_email(payload) do
  headers = [{"Content-Type", "application/json"}]
  api_url = classification_api_url()

  # Vérification que l'URL est définie
  if is_nil(api_url) do
    Logger.error("L'URL de l'API de classification n'est pas configurée")
    {:error, "Configuration manquante: URL de l'API de classification"}
  else
    case HTTPoison.post(api_url, Jason.encode!(payload), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, classification} ->
            {:ok, classification}
          {:error, reason} ->
            Logger.error("Erreur de décodage JSON: #{inspect(reason)}")
            {:error, "Erreur de décodage de la réponse: #{inspect(reason)}"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Erreur API (#{status_code}): #{body}")
        {:error, "Erreur API (#{status_code}): #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Erreur réseau: #{inspect(reason)}")
        {:error, "Erreur réseau: #{inspect(reason)}"}
    end
  end
end


  defp create_github_issue(message, classification, sender, body_text) do
    category = classification["category"]
    priority = classification["priority"]
    confidence = classification["confidence"]

    labels = [category, "priority:#{priority}"]

    title = "[#{String.upcase(category)}] #{message.subject}"

    issue_body = """
    ## Email de #{sender}

    _Reçu le: #{format_date(message.date)}_
    _Classification: #{category} (confiance: #{Float.round(confidence * 100, 2)}%)_
    _Priorité: #{priority}_

    ---

    #{body_text}

    ---

    _Référence email unique: #{generate_email_reference(message)}_
    """

    # Créer le ticket via le client GitHub
    case GithubClient.create_issue(title, issue_body, labels) do
      {:ok, issue} ->
        issue_number = issue["number"]
        Logger.info("Ticket GitHub ##{issue_number} créé avec succès pour l'email")
        {:ok, :issue_created, issue_number}

      {:error, reason} ->
        Logger.error("Échec de création du ticket GitHub: #{reason}")
        {:error, "Création du ticket échouée: #{reason}"}
    end
  end

  # Fonctions utilitaires reprises partiellement du module Handler
  # -----------------------------------------------

  # Fonction utilitaire pour formater la date
  defp format_date(date) do
    case date do
      nil -> "Date inconnue"
      date -> Calendar.strftime(date, "%d/%m/%Y %H:%M:%S")
    end
  end

  # Fonction pour extraire la partie texte d'un corps d'email
  defp extract_plaintext_body(body_parts) when is_list(body_parts) do
    Enum.find_value(body_parts, fn
      {"text/plain", _headers, content} -> content
      _ -> nil
    end) || ""
  end
  defp extract_plaintext_body(_), do: ""

  # Fonction pour formater l'expéditeur
  defp format_sender(sender) when is_list(sender) do
    case sender do
      [{name, email} | _] when is_binary(name) and name != "" -> "#{name} <#{email}>"
      [{_name, email} | _] -> email
      [email | _] when is_binary(email) -> email
      _ -> "Expéditeur inconnu"
    end
  end
  defp format_sender({name, email}) when is_binary(name) and is_binary(email) and name != "" do
    "#{name} <#{email}>"
  end
  defp format_sender({_name, email}) when is_binary(email), do: email
  defp format_sender(email) when is_binary(email), do: email
  defp format_sender(_), do: "Expéditeur inconnu"

  # Génère une référence unique pour l'email (pour faciliter le suivi)
  defp generate_email_reference(message) do
    hash_content = "#{message.subject}#{format_date(message.date)}#{inspect(message.sender)}"
    :crypto.hash(:md5, hash_content)
    |> Base.encode16(case: :lower)
    |> String.slice(0..7)
  end
end
