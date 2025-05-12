# lib/imap_api_client/application.ex
defmodule ImapApiClient.Application do
  require Logger
  @moduledoc """
  Démarre l'arbre du superviseur de l'application.
  """
  use Application

  @impl true
  def start(_type, _args) do
    Logger.info("Starting ImapApiClient Application...")

    # Initialise et démarre les process client Yugo basé sur la config
    # Ceci utilise la configuration de config/config.exs[:imap_clients]
    children = ImapApiClient.Imap.Client.init()

    # Ajoute notre GenServer EmailManager à l'arbre de supervision
    # Il lira sa config via Application.get_env
    children = children ++ [
      ImapApiClient.EmailManager,
      ImapApiClient.Github.GithubClient
    ]

    # Démarre le superviseur
    opts = [strategy: :one_for_one, name: ImapApiClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
