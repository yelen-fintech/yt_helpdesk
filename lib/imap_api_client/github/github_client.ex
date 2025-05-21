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

  @doc """
  Ajoute un commentaire à un ticket GitHub existant.
  """
  def add_comment(issue_number, comment_text) do
    GenServer.call(__MODULE__, {:add_comment, issue_number, comment_text})
  end

  @doc """
  Upload un fichier en tant qu'asset vers un ticket GitHub.

  Arguments:
  - issue_number: Le numéro du ticket GitHub
  - file_path: Le chemin du fichier à uploader
  - filename: Le nom du fichier (optionnel, par défaut le nom du fichier dans file_path)
  - description: Une description de l'asset (optionnel)

  Retourne:
  - {:ok, response_body} si réussi
  - {:error, reason} en cas d'échec
  """
  def upload_asset(issue_number, file_path, filename \\ nil, description \\ nil) do
    GenServer.call(__MODULE__, {:upload_asset, issue_number, file_path, filename, description}, 30_000)
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

      # URL de base pour les releases (utilisée pour les pièces jointes)
      releases_api_url = "https://api.github.com/repos/#{owner}/#{repo}/releases"

      state = %{
        base_api_url: base_api_url,
        base_headers: base_headers,
        releases_api_url: releases_api_url,
        owner: owner,
        repo: repo,
        token: token
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
  def handle_call({:add_comment, _issue_number, _comment_text}, _from, %{error: e} = state) do
    {:reply, {:error, "GitHub client not properly initialized: #{Exception.message(e)}"}, state}
  end

  @impl true
  def handle_call({:upload_asset, _issue_number, _file_path, _filename, _description}, _from, %{error: e} = state) do
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

    Logger.debug("Updating issue ##{issue_number} with: #{inspect(sanitized_data)}")

    case Jason.encode(sanitized_data) do
      {:ok, encoded_data} ->
        case HTTPoison.patch(url, encoded_data, headers) do
          {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
            {:reply, {:ok, Jason.decode!(body)}, state}
          {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
            Logger.error("Error updating issue ##{issue_number}: Status #{status_code}, Body: #{inspect(body)}")
            {:reply, {:error, "GitHub API error: #{status_code} - #{body}"}, state}
          {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.error("HTTP Error updating issue ##{issue_number}: #{inspect(reason)}")
            {:reply, {:error, "HTTP Error: #{inspect(reason)}"}, state}
        end
      {:error, reason} ->
        Logger.error("Failed to encode issue data: #{inspect(reason)}")
        {:reply, {:error, "JSON encoding error: #{inspect(reason)}"}, state}
    end
  end

  @impl true
  def handle_call({:add_comment, issue_number, comment_text}, _from, state) do
    url = "#{state.base_api_url}/#{issue_number}/comments"
    headers = state.base_headers ++ [{"Content-Type", "application/json"}]

    # Sanitize the comment text
    sanitized_comment = comment_text |> MimeUtils.sanitize_string()

    # Prepare the payload
    payload = %{body: sanitized_comment}

    case Jason.encode(payload) do
      {:ok, encoded_payload} ->
        case HTTPoison.post(url, encoded_payload, headers) do
          {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
            {:reply, {:ok, Jason.decode!(body)}, state}
          {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
            Logger.error("Error adding comment to issue ##{issue_number}: Status #{status_code}, Body: #{inspect(body)}")
            {:reply, {:error, "GitHub API error: #{status_code} - #{body}"}, state}
          {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.error("HTTP Error adding comment to issue ##{issue_number}: #{inspect(reason)}")
            {:reply, {:error, "HTTP Error: #{inspect(reason)}"}, state}
        end
      {:error, reason} ->
        Logger.error("Failed to encode comment data: #{inspect(reason)}")
        {:reply, {:error, "JSON encoding error: #{inspect(reason)}"}, state}
    end
  end

  @impl true
  def handle_call({:upload_asset, issue_number, file_path, filename, description}, _from, state) do
    # Pour GitHub, nous devons d'abord créer une release si elle n'existe pas déjà,
    # puis télécharger le fichier comme un asset de cette release

    # 1. Vérifier si le fichier existe
    case File.exists?(file_path) do
      false ->
        Logger.error("File not found: #{file_path}")
        {:reply, {:error, "File not found"}, state}

      true ->
        # 2. Obtenir des informations sur le fichier
        filename = filename || Path.basename(file_path)
        file_size = File.stat!(file_path).size

        # Vérifier si le fichier est trop grand (max 100MB pour GitHub, mais nous mettons une limite prudente)
        if file_size > 50_000_000 do # 50MB
          Logger.error("File too large (#{file_size} bytes): #{filename}")
          {:reply, {:error, "File too large. GitHub limit is 100MB"}, state}
        else
          # 3. Obtenir le type MIME du fichier
          mime_type = get_mime_type(filename)
          Logger.debug("Uploading file: #{filename} (#{mime_type}, #{file_size} bytes) to issue ##{issue_number}")

          # 4. Vérifier s'il existe une release pour ce numéro d'issue
          release_tag = "issue-#{issue_number}-assets"
          release_result = find_or_create_release(state, release_tag, issue_number)

          case release_result do
            {:ok, release_data} ->
              # 5. Télécharger le fichier comme asset de la release
              upload_result = upload_to_release(state, release_data, file_path, filename, mime_type)

              case upload_result do
                {:ok, asset_data} ->
                  # 6. Ajouter un commentaire à l'issue avec le lien vers l'asset
                  browser_url = asset_data["browser_download_url"]
                  comment_text = "File uploaded: [#{filename}](#{browser_url})"
                  if description, do: comment_text = comment_text <> "\n\n" <> description

                  # Ajouter le commentaire mais ne pas bloquer la réponse sur son résultat
                  spawn(fn -> add_comment(issue_number, comment_text) end)

                  {:reply, {:ok, asset_data}, state}

                {:error, reason} ->
                  Logger.error("Failed to upload asset: #{inspect(reason)}")
                  {:reply, {:error, reason}, state}
              end

            {:error, reason} ->
              Logger.error("Failed to find/create release: #{inspect(reason)}")
              {:reply, {:error, reason}, state}
          end
        end
    end
  end

  # Trouver ou créer une release pour le stockage d'assets
  defp find_or_create_release(state, tag, issue_number) do
    url = state.releases_api_url <> "/tags/#{tag}"
    headers = state.base_headers

    # Vérifier si la release existe déjà
    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        # La release existe
        {:ok, Jason.decode!(body)}

      _other ->
        # Créer une nouvelle release
        create_url = state.releases_api_url
        headers = headers ++ [{"Content-Type", "application/json"}]

        payload = %{
          tag_name: tag,
          name: "Assets for Issue ##{issue_number}",
          body: "This is an automatic release created to store assets for Issue ##{issue_number}",
          draft: false
        }

        case Jason.encode(payload) do
          {:ok, encoded_payload} ->
            case HTTPoison.post(create_url, encoded_payload, headers) do
              {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} when code in 200..299 ->
                {:ok, Jason.decode!(resp_body)}

              {:ok, %HTTPoison.Response{status_code: status_code, body: error_body}} ->
                {:error, "GitHub API error: #{status_code} - #{error_body}"}

              {:error, %HTTPoison.Error{reason: reason}} ->
                {:error, "HTTP Error: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, "JSON encoding error: #{inspect(reason)}"}
        end
    end
  end

  # Télécharger un fichier vers une release
  defp upload_to_release(state, release_data, file_path, filename, mime_type) do
    upload_url = String.replace(release_data["upload_url"], "{?name,label}", "")
    upload_url = upload_url <> "?name=#{URI.encode_www_form(filename)}"

    headers = state.base_headers ++ [
      {"Content-Type", mime_type},
      {"Content-Length", "#{File.stat!(file_path).size}"}
    ]

    # Lire le contenu du fichier
    case File.read(file_path) do
      {:ok, file_content} ->
        # Télécharger le fichier
        case HTTPoison.post(upload_url, file_content, headers) do
          {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
            {:ok, Jason.decode!(body)}

          {:ok, %HTTPoison.Response{status_code: status_code, body: error_body}} ->
            {:error, "GitHub API error: #{status_code} - #{error_body}"}

          {:error, %HTTPoison.Error{reason: reason}} ->
            {:error, "HTTP Error: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  # Déterminer le type MIME d'un fichier en fonction de son extension
  defp get_mime_type(filename) do
    extension = Path.extname(filename) |> String.downcase()

    case extension do
      ".pdf" -> "application/pdf"
      ".txt" -> "text/plain"
      ".html" -> "text/html"
      ".htm" -> "text/html"
      ".json" -> "application/json"
      ".xml" -> "application/xml"
      ".zip" -> "application/zip"
      ".doc" -> "application/msword"
      ".docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      ".xls" -> "application/vnd.ms-excel"
      ".xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      ".ppt" -> "application/vnd.ms-powerpoint"
      ".pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      ".gif" -> "image/gif"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".svg" -> "image/svg+xml"
      ".mp3" -> "audio/mpeg"
      ".mp4" -> "video/mp4"
      ".wav" -> "audio/wav"
      ".avi" -> "video/x-msvideo"
      ".csv" -> "text/csv"
      ".odt" -> "application/vnd.oasis.opendocument.text"
      ".ods" -> "application/vnd.oasis.opendocument.spreadsheet"
      ".odp" -> "application/vnd.oasis.opendocument.presentation"
      _ -> "application/octet-stream"  # Type par défaut
    end
  end
end
