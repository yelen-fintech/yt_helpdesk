defmodule ImapApiClient.Github.GithubClient do
  use GenServer
  require Logger

  # Importer les fonctions du module MimeUtils
  alias ImapApiClient.Utils.MimeUtils

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def list_issues do
    GenServer.call(__MODULE__, :list_issues)
  end

  def create_issue(title, body, labels \\ []) do
    GenServer.call(__MODULE__, {:create_issue, title, body, labels})
  end

  def update_issue(issue_number, data) do
    GenServer.call(__MODULE__, {:update_issue, issue_number, data})
  end

  def close_issue(issue_number) do
    update_issue(issue_number, %{state: "closed"})
  end

  # --- Server Callbacks ---
  @impl true
  def init(_opts) do
    Logger.info("GithubClient initializing...")

    try do
      # Load configuration
      config = Application.get_env(:imap_api_client, :github) || %{}
      token = config[:github_token] || System.get_env("GITHUB_TOKEN")
      owner = config[:owner] || System.get_env("GITHUB_OWNER")
      repo = config[:repo] || System.get_env("GITHUB_REPO")

      # Log loaded config values (except token) for debugging
      Logger.debug("GitHub configuration - Owner: #{owner}, Repo: #{repo}")
      Logger.debug("Token loaded: #{if token, do: "Yes", else: "No"}")

      # Check for missing values
      unless token && owner && repo do
        missing = []
        missing = if !token, do: missing ++ ["github_token"], else: missing
        missing = if !owner, do: missing ++ ["owner"], else: missing
        missing = if !repo, do: missing ++ ["repo"], else: missing

        raise "Missing GitHub configuration: #{Enum.join(missing, ", ")}"
      end

      # Construct the base API URL and headers
      base_api_url = "https://api.github.com/repos/#{owner}/#{repo}/issues"
      base_headers = [
        {"Authorization", "Bearer #{token}"},
        {"Accept", "application/vnd.github.v3+json"},
        {"User-Agent", "ElixirGitHubClientApp"}
      ]

      state = %{
        base_api_url: base_api_url,
        base_headers: base_headers
      }

      Logger.info("GithubClient initialized successfully.")
      {:ok, state}
    rescue
      e ->
        Logger.error("Error during GitHub client initialization: #{Exception.message(e)}")

        # Return an error state
        {:ok, %{error: e, base_api_url: nil, base_headers: []}}
    end
  end

  @impl true
  def handle_call(:list_issues, _from, %{error: e} = state) do
    {:reply, {:error, "GitHub client not properly initialized: #{Exception.message(e)}"}, state}
  end

  @impl true
  def handle_call({:create_issue, _title, _body, _labels}, _from, %{error: e} = state) do
    {:reply, {:error, "GitHub client not properly initialized: #{Exception.message(e)}"}, state}
  end

  @impl true
  def handle_call({:update_issue, _issue_number, _data}, _from, %{error: e} = state) do
    {:reply, {:error, "GitHub client not properly initialized: #{Exception.message(e)}"}, state}
  end

  @impl true
  def handle_call(:list_issues, _from, state) do
    url = state.base_api_url
    headers = state.base_headers
    Logger.debug("Listing issues from URL: #{url}")

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:reply, {:ok, Jason.decode!(body)}, state}
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Error listing issues: Status #{status_code}, Body: #{inspect(body)}")
        {:reply, {:error, "Error listing issues: #{status_code} - #{body}"}, state}
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP Error listing issues: #{inspect(reason)}")
        {:reply, {:error, "HTTP Error: #{inspect(reason)}"}, state}
    end
  end

  @impl true
  def handle_call({:create_issue, title, body, labels}, _from, state) do
    url = state.base_api_url
    headers = state.base_headers ++ [{"Content-Type", "application/json"}]

    # Décoder et sanitiser le titre (le titre est peut-être déjà décodé par MailFilter)
    sanitized_title = MimeUtils.decode_mime_header(title)

    # Traiter le corps en gérant spécifiquement les formats d'erreur observés dans les logs
    sanitized_body = cond do
      # Gérer le cas spécifique observé dans les logs: tuple avec 2 parties
      is_tuple(body) && tuple_size(body) == 3 && elem(body, 0) == :error &&
      is_binary(elem(body, 1)) && is_binary(elem(body, 2)) ->
        prefix = elem(body, 1)
        binary_data = elem(body, 2)
        prefix <> MimeUtils.sanitize_string(binary_data)

      # Cas standard pour binaire
      is_binary(body) ->
        MimeUtils.convert_body_to_utf8(body) |> MimeUtils.sanitize_string()

      # Cas pour listes
      is_list(body) ->
        body |> List.to_string() |> MimeUtils.sanitize_string()

      # Cas nil
      is_nil(body) ->
        ""

      # Fallback pour tout autre cas
      true ->
        MimeUtils.safe_to_string(body)
    end

    # Logging sécurisé
    safe_body_preview = if is_binary(sanitized_body),
      do: String.slice(sanitized_body, 0..100),
      else: inspect(sanitized_body)

    Logger.debug("Sanitized title: #{inspect(sanitized_title)}")
    Logger.debug("Sanitized body (preview): #{safe_body_preview}")

    # Sanitiser les labels
    sanitized_labels = Enum.map(labels, &MimeUtils.sanitize_string/1)

    # Construire le payload
    payload = %{
      title: sanitized_title || "Titre non décodable",
      body: sanitized_body || "Contenu non décodable",
      labels: sanitized_labels
    }

    # Encoder le payload en JSON avec capture d'erreur
    encoded_payload = try do
      Jason.encode!(payload)
    rescue
      e in Jason.EncodeError ->
        Logger.error("JSON encoding error: #{Exception.message(e)}")
        Logger.error("Problematic data: title=#{inspect(sanitized_title)}, labels=#{inspect(sanitized_labels)}")
        Logger.error("Body preview: #{safe_body_preview}")

        # Essayer une version dégradée
        Jason.encode!(%{
          title: if(is_binary(sanitized_title), do: sanitized_title, else: "Untitled Issue"),
          body: if(is_binary(sanitized_body), do: sanitized_body, else: "[Contenu original non encodable en JSON - voir les logs]"),
          labels: Enum.filter(sanitized_labels, &is_binary/1)
        })
    end

    case HTTPoison.post(url, encoded_payload, headers) do
      {:ok, %HTTPoison.Response{status_code: 201, body: resp_body}} ->
        {:reply, {:ok, Jason.decode!(resp_body)}, state}
      {:ok, %HTTPoison.Response{status_code: status_code, body: resp_body}} ->
        Logger.error("Error creating issue: Status #{status_code}, Body: #{inspect(resp_body)}")
        {:reply, {:error, "Error creating issue: #{status_code} - #{resp_body}"}, state}
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP Error creating issue: #{inspect(reason)}")
        {:reply, {:error, "HTTP Error: #{inspect(reason)}"}, state}
    end
  end

  @impl true
  def handle_call({:update_issue, issue_number, data}, _from, state) do
    url = "#{state.base_api_url}/#{issue_number}"
    headers = state.base_headers ++ [{"Content-Type", "application/json"}]

    # Sanitize all string values in the data map
    sanitized_data = case data do
      map when is_map(map) ->
        Enum.into(map, %{}, fn {k, v} ->
          {k, if(is_binary(v), do: MimeUtils.sanitize_string(v), else: v)}
        end)
      other ->
        Logger.warning("Non-map data passed to update_issue: #{inspect(other)}")
        other
    end

    payload = Jason.encode!(sanitized_data)
    Logger.debug("Updating issue ##{issue_number} at URL: #{url} with payload: #{inspect(payload)}")

    case HTTPoison.patch(url, payload, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        {:reply, {:ok, Jason.decode!(resp_body)}, state}
      {:ok, %HTTPoison.Response{status_code: status_code, body: resp_body}} ->
        Logger.error("Error updating issue ##{issue_number}: Status #{status_code}, Body: #{inspect(resp_body)}")
        {:reply, {:error, "Error updating issue ##{issue_number}: #{status_code} - #{resp_body}"}, state}
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP Error updating issue ##{issue_number}: #{inspect(reason)}")
        {:reply, {:error, "HTTP Error: #{inspect(reason)}"}, state}
    end
  end
end
