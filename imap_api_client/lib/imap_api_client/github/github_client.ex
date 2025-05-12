defmodule ImapApiClient.Github.GithubClient do
  use GenServer
  require Logger

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
      # Récupérer les valeurs de configuration
      config = Application.get_env(:imap_api_client, :github) || %{}
      token = config[:github_token] || System.get_env("GITHUB_TOKEN")
      owner = config[:github_owner] || System.get_env("GITHUB_OWNER")
      repo = config[:github_repo] || System.get_env("GITHUB_REPO")

      # Vérifions que les valeurs requises sont présentes
      unless token && owner && repo do
        missing = []
        missing = if !token, do: missing ++ ["github_token"], else: missing
        missing = if !owner, do: missing ++ ["github_owner"], else: missing
        missing = if !repo, do: missing ++ ["github_repo"], else: missing

        raise "Missing GitHub configuration: #{Enum.join(missing, ", ")}"
      end

      # Construire l'URL de l'API GitHub correctement
      base_api_url = "https://api.github.com/repos/#{owner}/#{repo}/issues"

      base_headers = [
        {"Authorization", "token #{token}"},
        {"Accept", "application/vnd.github.v3+json"},
        {"User-Agent", "ElixirGitHubClientApp"}
      ]

      state = %{
        base_api_url: base_api_url,
        base_headers: base_headers
      }
      Logger.info("GithubClient initialized successfully")
      {:ok, state}
    rescue
      e ->
        Logger.error("Error during GitHub client initialization: #{Exception.message(e)}")
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
    payload = Jason.encode!(%{title: title, body: body, labels: labels})

    case HTTPoison.post(url, payload, headers) do
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
    payload = Jason.encode!(data)
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
