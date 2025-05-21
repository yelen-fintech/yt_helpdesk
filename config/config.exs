import Config

# Charger les variables d'environnement
if File.exists?(".env") do
  File.read!(".env")
  |> String.split("\n", trim: true)
  |> Enum.each(fn line ->
    if String.contains?(line, "=") do
      [key, value] = String.split(line, "=", parts: 2)
      System.put_env(String.trim(key), String.trim(value))
    end
  end)
end

config :logger, level: :debug

config :imap_api_client, ImapApiClient.EmailManager,
  imap_client_name: :infomaniak_imap_client,
  attachments_enabled: true,
  attachments_dir: "priv/attachments",
  smtp_mailer: ImapApiClient.Mailer,
  email_address: System.get_env("EMAIL_ADDRESS")

config :imap_api_client, :imap_clients, [
  infomaniak_imap_client: [
    server: System.get_env("IMAP_SERVER"),
    port: String.to_integer(System.get_env("IMAP_PORT", "993")),
    ssl: true,
    username: System.get_env("IMAP_USERNAME"),
    password: System.get_env("IMAP_PASSWORD"),
    auth_type: :plain
  ]
]

config :imap_api_client, :github,
  github_token: System.get_env("GITHUB_TOKEN"),
  owner: System.get_env("GITHUB_OWNER"),
  repo: System.get_env("GITHUB_REPO")
