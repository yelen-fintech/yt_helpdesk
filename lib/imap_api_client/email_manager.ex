defmodule ImapApiClient.EmailManager do
  @moduledoc """
  GenServer pour gérer l'écoute IMAP et l'envoi SMTP.
  """

  use GenServer
  require Logger
  alias ImapApiClient.Imap.{Client, Handler, Filter}
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
      result = Handler.handle_message(message)

      case result do
        {:ok, :issue_created, issue_number} ->
          Logger.info("Email processing successful: GitHub issue ##{issue_number} created.")


        {:error, reason} ->
          Logger.error("Failed to process email: #{reason}")

        unexpected ->
          Logger.error("Unexpected result from Handler: #{inspect(unexpected)}")
      end
    rescue
      e ->
        stacktrace = Process.info(self(), :current_stacktrace) |> elem(1) |> Exception.format_stacktrace()
        Logger.error("Exception while processing email: #{Exception.message(e)}")
        Logger.error("#{stacktrace}")
    end
  end

end
