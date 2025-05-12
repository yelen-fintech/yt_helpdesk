defmodule ImapApiClient.Patch do
  @moduledoc """
  Module pour appliquer des correctifs temporaires à l'application.
  Idéal pour tester des solutions sans modifier la structure principale.
  """

  require Logger
  alias ImapApiClient.Imap.DebugHandler

  @doc """
  Applique le patch pour la gestion des pièces jointes.
  À utiliser directement depuis IEx:

  ```
  ImapApiClient.Patch.apply_attachment_patch()
  ```
  """
  def apply_attachment_patch do
    IO.puts("Application du patch pour la gestion des pièces jointes...")

    # 1. Injecter un hook dans le système de traitement des messages
    :ok = inject_debug_handler()

    IO.puts("""

    Patch appliqué avec succès!

    Lorsqu'un nouvel email arrivera, il sera analysé en profondeur et
    des tentatives d'extraction des pièces jointes seront effectuées.

    Le résultat sera affiché dans la console et les fichiers seront
    sauvegardés dans le dossier 'attachments_debug'.

    Vous pouvez également déboguer un message manuellement avec:

    ```
    # Remplacer message_var par la variable contenant le message
    ImapApiClient.Imap.DebugHandler.debug_message_structure(message_var)
    ImapApiClient.Imap.DebugHandler.force_save_attachments(message_var)
    ```
    """)
  end

  @doc """
  Injecte le gestionnaire de débogage dans le pipeline de traitement des messages.
  """
  def inject_debug_handler do
    # Cette fonction utilise le méta-programmation pour injecter notre code
    # dans le processus de traitement des messages sans modifier les fichiers sources

    Logger.info("Injection du gestionnaire de débogage des pièces jointes...")

    # Localiser tous les modules potentiels de traitement des emails
    modules = [
      ImapApiClient.Imap.Handler,
      ImapApiClient.EmailManager,
      ImapApiClient.EmailProcessor
    ] ++ find_email_modules()

    # Injecter notre handler dans chaque module
    Enum.each(modules, fn module ->
      if Code.ensure_loaded?(module) do
        # Sauvegarder la fonction originale handle_message si elle existe
        if function_exported?(module, :handle_message, 1) do
          Logger.info("Injection dans #{inspect(module)}.handle_message/1")

          original_fun = :erlang.make_fun(module, :handle_message, 1)

          # Définir une nouvelle fonction qui appelle notre débogueur puis la fonction originale
          defoverridable_module(module, handle_message: 1)

          Module.define_function(module, :handle_message, quote do
            def handle_message(message) do
              # Appeler notre débogueur
              message = ImapApiClient.Imap.DebugHandler.debug_message_structure(message)
              ImapApiClient.Imap.DebugHandler.force_save_attachments(message)

              # Puis appeler la fonction originale
              unquote(original_fun).(message)
            end
          end)

          Logger.info("Handler de débogage injecté dans #{inspect(module)}")
        end
      end
    end)

    :ok
  end

  # Fonction pour rendre un module "defoverridable" dynamiquement
  defp defoverridable_module(module, functions) do
    Module.put_attribute(module, :defoverridable, functions)
  end

  # Recherche dynamique de modules qui pourraient traiter des emails
  defp find_email_modules do
    app_modules = :application.get_key(:imap_api_client, :modules)

    case app_modules do
      {:ok, modules} ->
        Enum.filter(modules, fn module ->
          module_name = Atom.to_string(module)
          String.contains?(module_name, "Email") or
          String.contains?(module_name, "Mail") or
          String.contains?(module_name, "Imap") or
          String.contains?(module_name, "Message")
        end)

      _ -> []
    end
  end

  @doc """
  Un hook simple pour intercepter les messages IMAP bruts avant tout traitement.

  À utiliser comme ceci depuis IEx si vous avez accès au client IMAP:

  ```
  # Supposons que votre client IMAP est dans une variable client_imap
  ImapApiClient.Patch.hook_raw_imap_messages(client_imap)
  ```
  """
  def hook_raw_imap_messages(imap_client) do
    IO.puts("Installation d'un hook pour les messages IMAP bruts...")

    # Cette fonction est hypothétique et devra être adaptée selon
    # l'implémentation spécifique de votre client IMAP

    # Un exemple hypothétique:
    if function_exported?(imap_client.__struct__, :add_listener, 2) do
      imap_client.__struct__.add_listener(imap_client, fn raw_message ->
        IO.puts("\n===== MESSAGE IMAP BRUT INTERCEPTÉ =====")

        # Enregistrer le message brut dans un fichier
        raw_file = "raw_imap_#{DateTime.utc_now() |> DateTime.to_unix()}.txt"
        File.write!(raw_file, inspect(raw_message, limit: :infinity, pretty: true))

        IO.puts("Message IMAP brut enregistré dans: #{raw_file}")

        # Continuer le traitement normal
        :continue
      end)

      IO.puts("Hook installé avec succès!")
    else
      IO.puts("Impossible d'installer le hook: méthode add_listener non disponible")
    end
  end
end
