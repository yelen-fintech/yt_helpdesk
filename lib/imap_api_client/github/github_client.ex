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
      # Load configuration
      config = Application.get_env(:imap_api_client, :github) || %{}
      # Fix: Changed fine_token to github_token
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

    # Décoder et sanitiser le titre
    sanitized_title = decode_mime_header(title)
    
    # Traiter le corps selon son format
    sanitized_body = cond do
      is_binary(body) -> 
        sanitize_string(body)
      is_list(body) -> 
        List.to_string(body) |> sanitize_string()
      # Gérer le cas spécial des binaires (<<...>>)
      true -> 
        try do
          # Essayer de le convertir en chaîne UTF-8
          if is_binary(body) do
            :unicode.characters_to_binary(body, :latin1, :utf8)
          else
            bin_body = IO.iodata_to_binary(body)
            :unicode.characters_to_binary(bin_body, :latin1, :utf8)
          end
        rescue
          e ->
            Logger.error("Failed to convert body to UTF-8: #{Exception.message(e)}")
            Logger.error("Body type: #{inspect(typeof(body))}")
            Logger.error("Body preview: #{inspect(body, limit: 100)}")
            # Fallback: traiter comme une chaîne ASCII
            try do
              if is_binary(body) do
                body
                |> :binary.bin_to_list()
                |> Enum.filter(fn byte -> byte < 128 end)
                |> List.to_string()
              else
                inspect(body)
              end
            rescue
              _ -> "[Content could not be encoded properly]"
            end
        end
    end
    
    sanitized_labels = Enum.map(labels, &sanitize_string/1)

    # Logging pour le débogage
    Logger.debug("Sanitized title: #{inspect(sanitized_title)}")
    Logger.debug("Sanitized body (preview): #{String.slice(to_string(sanitized_body), 0..100)}")

    # Construire le payload
    payload = %{
      title: sanitized_title,
      body: sanitized_body,
      labels: sanitized_labels
    }

    # Encoder le payload en JSON avec capture d'erreur
    encoded_payload = try do
      Jason.encode!(payload)
    rescue
      e in Jason.EncodeError ->
        Logger.error("JSON encoding error: #{Exception.message(e)}")
        Logger.error("Problematic data: title=#{inspect(sanitized_title)}, labels=#{inspect(sanitized_labels)}")
        Logger.error("Body preview: #{String.slice(to_string(sanitized_body), 0..100)}")
        
        # Essayer une version dégradée
        Jason.encode!(%{
          title: if(is_binary(sanitized_title), do: sanitized_title, else: "Untitled Issue"),
          body: "[Contenu original non encodable en JSON - voir les logs]",
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

    # Sanitizer les données pour s'assurer qu'elles sont en UTF-8 valide
    sanitized_data = sanitize_map(data)

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

  # ----- Helper functions for encoding sanitization -----

  # Helper pour déterminer le type d'une variable
  defp typeof(self) do
    cond do
      is_float(self)    -> "float"
      is_number(self)   -> "number"
      is_atom(self)     -> "atom"
      is_boolean(self)  -> "boolean"
      is_binary(self)   -> "binary"
      is_function(self) -> "function"
      is_list(self)     -> "list"
      is_tuple(self)    -> "tuple"
      is_map(self)      -> "map"
      is_pid(self)      -> "pid"
      is_port(self)     -> "port"
      is_reference(self) -> "reference"
      true              -> "unknown"
    end
  end

  # Décode les en-têtes MIME (comme ceux encodés avec =?charset?encoding?encoded-text?=)
  defp decode_mime_header(header) when is_binary(header) do
    if String.match?(header, ~r/=\?[\w-]+\?[QB]\?.*?\?=/) do
      # Trouver toutes les parties encodées
      Regex.replace(~r/=\?([\w-]+)\?([QB])\?(.*?)\?=/, header, fn whole_match, charset, encoding, content ->
        case encoding do
          "Q" ->
            # Décodage Q-encoding
            decoded = content
                      |> String.replace("_", " ")
                      |> String.replace(~r/=([0-9A-F]{2})/i, fn _, hex -> 
                         <<String.to_integer(hex, 16)>> 
                      end)
            
            # Conversion vers UTF-8
            :unicode.characters_to_binary(decoded, String.to_atom(String.downcase(charset)), :utf8)
            
          "B" ->
            # Décodage Base64
            try do
              decoded = Base.decode64!(content)
              :unicode.characters_to_binary(decoded, String.to_atom(String.downcase(charset)), :utf8)
            rescue
              _ -> whole_match  # Conserver le texte original en cas d'erreur
            end
            
          _ -> whole_match
        end
      end)
    else
      # Si ce n'est pas un encodage MIME, utiliser la sanitisation normale
      sanitize_string(header)
    end
  end
  defp decode_mime_header(nil), do: nil
  defp decode_mime_header(other), do: sanitize_string(to_string(other))

  # Sanitise une chaîne pour s'assurer qu'elle est en UTF-8 valide
  defp sanitize_string(nil), do: nil
  defp sanitize_string(str) when is_binary(str) do
    try do
      # Essayer d'abord avec latin1 (iso-8859-1) vers UTF-8
      case :unicode.characters_to_binary(str, :latin1, :utf8) do
        result when is_binary(result) -> result
        _ ->
          # Si ça échoue, essayer de nettoyer les caractères non-UTF8
          str
          |> String.codepoints()
          |> Enum.filter(fn char -> String.valid?(char) end)
          |> Enum.join("")
      end
    rescue
      _ ->
        # Fallback: traiter comme une liste de bytes et filtrer ceux qui ne sont pas valides en UTF-8
        str
        |> :binary.bin_to_list()
        |> Enum.filter(fn byte -> byte < 128 end)  # Garder seulement les ASCII
        |> List.to_string()
    end
  end
  defp sanitize_string(other), do: inspect(other)

  # Sanitiser une liste
  defp sanitize_list(list) when is_list(list) do
    Enum.map(list, fn
      item when is_binary(item) -> sanitize_string(item)
      item when is_map(item) -> sanitize_map(item)
      item when is_list(item) -> sanitize_list(item)
      item -> item
    end)
  end

  # Sanitiser une map récursivement
  defp sanitize_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      sanitized_value = cond do
        is_binary(v) -> sanitize_string(v)
        is_map(v) -> sanitize_map(v)
        is_list(v) -> sanitize_list(v)
        true -> v
      end
      Map.put(acc, k, sanitized_value)
    end)
  end
  defp sanitize_map(other), do: other
end
