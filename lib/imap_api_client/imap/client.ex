# lib/imap_api_client/imap/client.ex
defmodule ImapApiClient.Imap.Client do
  @moduledoc """
  Gestion des clients IMAP.
  """

  require Logger

  @doc """
  Initialise les clients IMAP à partir de la configuration.
  """
  def init do
    imap_clients = Application.get_env(:imap_api_client, :imap_clients, [])

    for {name, config} <- imap_clients do
      {Yugo.Client, Keyword.merge([name: name], config)}
    end
  end

  @doc """
  Vérifie la connexion IMAP pour un client spécifique.
  """
  # Dans lib/imap_api_client/imap/client.ex
def check_connection(client_name) do

  # Liste tous les processus enregistrés pour le déboggage
  _registered_processes = Process.registered()

  # Essayer de convertir le nom du client en PID
  client_pid = case client_name do
    name when is_atom(name) ->
      pid = Process.whereis(name)
      pid
    pid when is_pid(pid) -> pid
    _ -> nil
  end

  case client_pid do
    nil ->
      # Si le PID n'est pas trouvé, vérifiez si le client est un GenServer sous un autre nom
      alt_pid = try_find_client_by_module(client_name)
      case alt_pid do
        nil ->
          {:error, "Client IMAP non trouvé: #{inspect(client_name)}"}
        _pid ->
          {:ok, "Client IMAP connecté et actif"}
      end

    pid when is_pid(pid) ->
      if Process.alive?(pid) do
        {:ok, "Client IMAP connecté et actif"}
      else
        {:error, "Client IMAP inactif"}
      end
  end
end

# Fonction auxiliaire pour trouver un processus par son module
defp try_find_client_by_module(_client_name) do
  # Cette fonction tente de trouver un processus qui utilise le module Yugo.Client
  # Elle parcourt tous les processus du système et cherche ceux qui ont le bon module

  Process.list()
  |> Enum.find_value(fn pid ->
    info = Process.info(pid, [:registered_name, :dictionary])
    cond do
      # Vérifie si le processus a un dictionnaire avec '$initial_call' configuré à {Yugo.Client, _, _}
      is_list(info) &&
      is_list(info[:dictionary]) &&
      Keyword.get(info[:dictionary], :"$initial_call") == {Yugo.Client, :init, 1} ->
        pid
      true ->
        false
    end
  end)
end

end
