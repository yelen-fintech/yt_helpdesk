defmodule ImapApiClient.EmailManager do
  @moduledoc """
  GenServer pour gérer l'écoute IMAP et l'envoi SMTP.
  """

  use GenServer
  require Logger
  alias ImapApiClient.Imap.Client
  alias ImapApiClient.Imap.Filter
  alias ImapApiClient.Classifier.Model
  alias ImapApiClient.Github.MailFilter
  alias Swoosh.Email

  @email_manager_config Application.compile_env(:imap_api_client, __MODULE__, [])
  @imap_client_name Keyword.fetch!(@email_manager_config, :imap_client_name)
  @smtp_mailer Keyword.fetch!(@email_manager_config, :smtp_mailer)
  @email_address Keyword.fetch!(@email_manager_config, :email_address)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def send_email(recipients, subject, body) do
    sender = @email_address
    GenServer.call(__MODULE__, {:send_email, sender, recipients, subject, body})
  end

  @impl true
  def init(:ok) do
    Logger.info("Starting EmailManager GenServer for address: #{@email_address}")

    case Process.whereis(@imap_client_name) do
      nil ->
        Logger.info("IMAP client #{@imap_client_name} not found, attempting to start it...")
        start_imap_client()

      _pid ->
        Logger.info("IMAP client #{@imap_client_name} already running.")
    end

    case Client.check_connection(@imap_client_name) do
      {:ok, msg} -> Logger.info(msg)
      {:error, reason} ->
        Logger.error("IMAP client check failed: #{reason}")
    end

    filter = Filter.build_filter([])

    try do
      Yugo.subscribe(@imap_client_name, filter)
      Logger.info("Subscription successful.")
      schedule_check_mail()
      {:ok, %{imap_client_name: @imap_client_name, filter: filter}}
    rescue
      e ->
        Logger.error("Failed to subscribe: #{inspect e}")
        {:stop, {:subscription_failed, e}}
    end
  end

  defp start_imap_client do
    config = Application.get_env(:imap_api_client, :imap_clients, %{})[@imap_client_name]

    if config do

      # Convertir la map en keyword list si nécessaire
      config_kw = if is_map(config), do: Enum.into(config, []), else: config

      # Ajouter le nom au client
      client_config = Keyword.merge([name: @imap_client_name], config_kw)

      case Yugo.Client.start_link(client_config) do
        {:ok, pid} ->
          Logger.info("IMAP client started successfully: #{inspect(pid)}")
          {:ok, pid}

        {:error, {:already_started, pid}} ->
          {:ok, pid}

        {:error, reason} ->
          Logger.error("Failed to start IMAP client: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("No configuration found for IMAP client: #{@imap_client_name}")
      {:error, :no_config}
    end
  end

  defp schedule_check_mail do
    Process.send_after(self(), :check_mail, 5 * 60 * 1000)
  end

  def check_mail do
    Logger.info("Checking mail...")
  end

  @impl true
  def handle_call({:send_email, sender, recipients, subject, body}, _from, state) do

    email =
      %Email{}
      |> Email.to(recipients)
      |> Email.from(sender)
      |> Email.subject(subject)
      |> Email.text_body(body)

    result = @smtp_mailer.deliver(email)

    case result do
      {:ok, _response} ->
        Logger.info("Email envoyé avec succès !")

      {:error, reason} ->
        Logger.error("Échec de l'envoi : #{inspect reason}")
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call(msg, _from, state) do
    Logger.warning("Received unexpected call: #{inspect msg}")
    {:reply, {:error, :unhandled_call}, state}
  end

  @impl true
  def handle_info(msg, state) do
    case msg do
      :check_mail ->
        Logger.debug("Performing scheduled mail check")
        check_mail()
        schedule_check_mail()
        {:noreply, state}

      {:email, _client_name, message} ->
        spawn_link(fn -> process_email(message) end)
        {:noreply, state}

      {:ok, :issue_created, issue_number} ->
        Logger.info("Email successfully processed and ticket ##{issue_number} created.")
        {:noreply, state}

      {:error, :processing_failed, reason} ->
        Logger.error("Email processing failed: #{reason}")
        {:noreply, state}

      {:DOWN, _ref, :process, pid, reason} ->
        Logger.warning("Process surveillé terminé : PID #{inspect pid}, Raison : #{inspect reason}")
        {:noreply, state}

      _ ->
        Logger.warning("Received unexpected info: #{inspect msg}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.warning("Received unexpected cast: #{inspect msg}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("EmailManager terminating with reason #{inspect reason}")

    case Yugo.unsubscribe(state.imap_client_name) do
      :ok -> Logger.info("Unsubscribed from Yugo.")
    end

    :ok
  end

  defp process_email(message) do
    try do
      Logger.info("Traitement de l'email pour classification...")

      # Extraire les informations de l'email pour la classification
      email_info = extract_basic_email_info(message)

      # Utiliser le modèle de classification pour obtenir la catégorie et l'urgence
      classification_result = Model.classify_email("#{email_info.subject}\n\n#{email_info.body}")

      # Transformer le résultat de la classification pour le format attendu par MailFilter
      classification = %{
        category: Map.get(classification_result, :predicted_category),
        priority: Map.get(classification_result, :predicted_urgency),
        confidence: get_confidence_from_scores(classification_result),
        labels: []
      }

      # Transmettre le message et la classification à MailFilter
      result = MailFilter.process_email(message, classification)

      case result do
        {:ok, :issue_created, issue_number} ->
          Logger.info("Email processing successful: GitHub issue ##{issue_number} created.")

        {:error, reason} ->
          Logger.error("Failed to process email: #{reason}")

      end
    rescue
      e ->
        stacktrace = Process.info(self(), :current_stacktrace) |> elem(1) |> Exception.format_stacktrace()
        Logger.error("Exception while processing email: #{Exception.message(e)}")
        Logger.error("#{stacktrace}")
    end
  end

  # Extraction des informations de base de l'email pour la classification
  defp extract_basic_email_info(message) do
    # Fonction simplifiée pour extraire juste ce dont on a besoin pour la classification
    subject = extract_field(message, "subject") || ""
    body = extract_body(message) || ""

    %{
      subject: subject,
      body: body
    }
  end

  # Extraire un champ d'en-tête (version simplifiée)
  defp extract_field(message, field_name) do
    cond do
      is_nil(message) || message == %{} ->
        nil

      Map.has_key?(message, :fields) && Map.has_key?(message.fields, String.to_atom(field_name)) ->
        message.fields[String.to_atom(field_name)]

      Map.has_key?(message, :headers) && is_list(message.headers) ->
        Enum.find_value(message.headers, nil, fn
          {header, value} when is_binary(header) ->
            if String.downcase(header) == String.downcase(field_name), do: value, else: nil
          _ -> nil
        end)

      Map.has_key?(message, String.to_atom(field_name)) ->
        Map.get(message, String.to_atom(field_name))

      true ->
        nil
    end
  end

# Extraire le corps du message
defp extract_body(message) do
  cond do
    is_nil(message) ->
      nil

    # Si le corps est une liste (MIME parts multiples)
    Map.has_key?(message, :body) && is_list(message.body) ->
      # Tenter d'extraire la partie text/plain d'abord
      Enum.find_value(message.body, fn
        {"text/plain", _attrs, content} when is_binary(content) -> content
        {"text/html", _attrs, content} when is_binary(content) -> content
        _ -> nil
      end)

    Map.has_key?(message, :body) && is_binary(message.body) ->
      message.body

    Map.has_key?(message, :body) && Map.has_key?(message.body, :text) ->
      message.body.text

    Map.has_key?(message, :body) && Map.has_key?(message.body, :html) ->
      message.body.html

    true ->
      nil
  end
end

  # Calculer un score de confiance global à partir des scores de classification
  defp get_confidence_from_scores(classification_result) do
    # Obtenir le premier score de catégorie (le plus élevé)
    category_confidence = case classification_result do
      %{category_scores: [{_, score} | _]} -> score
      _ -> 0.5
    end

    # Obtenir le premier score d'urgence (le plus élevé)
    urgency_confidence = case classification_result do
      %{urgency_scores: [{_, score} | _]} -> score
      _ -> 0.5
    end

    # Moyenne des deux scores comme confiance globale
    (category_confidence + urgency_confidence) / 2
  end
end
