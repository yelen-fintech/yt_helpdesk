defmodule Classification.IntegrationTest do
  @moduledoc """
  Module pour tester l'intégration du système de classification des emails.
  Ce module simule le processus complet et affiche les résultats.
  """

  alias Classification.EmailClassifier
  alias Classification.ModelTrainer

  require Logger

  @doc """
  Exécute un test du processus complet de classification des emails :
  1. Démarre le classificateur s'il n'est pas déjà en cours d'exécution
  2. Entraîne le modèle avec les données disponibles
  3. Classifie quelques emails de test
  4. Affiche les résultats
  """

  alias Classification.EmailClassifier
  alias Classification.ModelTrainer

  require Logger


  def test_email_processing do
    Logger.info("Démarrage du test d'intégration de classification d'emails")

    # 1. S'assurer que le classificateur est démarré
    start_classifier_if_needed()

    # 2. Signaler le début du test
    Logger.info("État initial du système de classification")

    # 3. Entraîner le modèle
    Logger.info("Entraînement du modèle...")
    case ModelTrainer.train_all() do
      {:ok, summary} ->
        Logger.info("Entraînement terminé. Résumé: #{inspect(summary)}")

      {:error, reason} ->
        Logger.warning("Entraînement échoué: #{inspect(reason)}")
    end

    # 4. Indiquer que l'entraînement est terminé
    Logger.info("Le modèle a été entraîné et est prêt à classifier des emails")

    # 5. Classifier quelques emails de test
    test_emails = [
      %{
        subject: "Problème de connexion à mon compte",
        body: "Je n'arrive pas à me connecter à mon compte client. Mon identifiant est correct mais mon mot de passe ne fonctionne pas."
      },
      %{
        subject: "Quand sera livrée ma commande #12345?",
        body: "Bonjour, j'ai passé commande il y a 3 jours mais je n'ai toujours pas reçu de confirmation d'expédition. Pouvez-vous me dire quand elle sera livrée?"
      },
      %{
        subject: "Remboursement demandé",
        body: "J'ai demandé un remboursement pour ma commande défectueuse il y a une semaine, mais je n'ai toujours rien reçu sur ma carte bancaire."
      },
      %{
        subject: "Bug sur votre site web",
        body: "Il y a un problème technique sur votre site de réservation. Quand je clique sur 'Confirmer', j'obtiens une erreur 404."
      }
    ]

    # Classifier chaque email et afficher le résultat
    for {email, index} <- Enum.with_index(test_emails, 1) do
      result = EmailClassifier.classify(email)

      IO.puts("\n--- Email de test ##{index} ---")
      IO.puts("Sujet: #{email.subject}")
      IO.puts("Extrait du corps: #{String.slice(email.body, 0, 50)}...")
      IO.puts("\nRésultat de classification:")
      IO.puts("- Catégorie: #{result.category}")
      IO.puts("- Priorité: #{result.priority}")
      IO.puts("- Labels: #{inspect(result.labels)}")
      IO.puts("- Confiance: #{result.confidence}")
    end

    # 6. Si vous avez un ensemble d'évaluation, mesurer les performances
    try_evaluation()

    :ok
  end

  @doc """
  Crée un fichier de données d'entraînement avec des exemples
  pour aider à démarrer le système.
  """
  def create_sample_training_data do
    # Créer des exemples d'emails avec leurs classifications
    sample_data = [
      %{
        "subject" => "Problème de connexion",
        "body" => "Je n'arrive pas à me connecter à mon compte client. Mon mot de passe ne fonctionne pas.",
        "category" => "account",
        "priority" => "high",
        "labels" => ["login", "password"]
      },
      %{
        "subject" => "Commande non reçue",
        "body" => "Bonjour, j'ai commandé il y a 5 jours et je n'ai toujours pas reçu mon colis.",
        "category" => "order",
        "priority" => "medium",
        "labels" => ["delivery", "delay"]
      },
      %{
        "subject" => "Demande de remboursement",
        "body" => "Le produit ne correspond pas à mes attentes, je souhaite être remboursé.",
        "category" => "payment",
        "priority" => "medium",
        "labels" => ["refund"]
      },
      %{
        "subject" => "Site web inaccessible",
        "body" => "Je ne parviens pas à accéder à votre site web depuis ce matin.",
        "category" => "technical",
        "priority" => "high",
        "labels" => ["website", "access"]
      },
      %{
        "subject" => "Question sur les délais de livraison",
        "body" => "Dans combien de temps sera livrée ma commande n°12345?",
        "category" => "order",
        "priority" => "low",
        "labels" => ["delivery", "question"]
      }
    ]

    # Créer le répertoire de données si nécessaire
    data_dir = "priv/data/json"
    File.mkdir_p!(data_dir)

    # Enregistrer les exemples dans un fichier JSON
    file_path = "#{data_dir}/sample_training_data.json"
    File.write!(file_path, Jason.encode!(sample_data, pretty: true))

    Logger.info("Données d'exemple sauvegardées dans #{file_path}")
    {:ok, file_path}
  end

  # Fonctions privées

  defp start_classifier_if_needed do
    # Vérifier si le classificateur est déjà en cours d'exécution
    if Process.whereis(EmailClassifier) == nil do
      Logger.info("Démarrage du classificateur...")
      {:ok, _pid} = EmailClassifier.start_link([])
      Logger.info("Classificateur démarré")
    else
      Logger.info("Classificateur déjà en cours d'exécution")
    end
  end

  defp try_evaluation do
    eval_file = "priv/data/json/evaluation_data.json"
    if File.exists?(eval_file) do
      Logger.info("Évaluation des performances du modèle...")
      case ModelTrainer.evaluate(eval_file) do
        {:ok, metrics} ->
          Logger.info("Évaluation terminée. Métriques: #{inspect(metrics)}")
        {:error, reason} ->
          Logger.warning("Évaluation échouée: #{inspect(reason)}")
      end
    else
      Logger.info("Aucun fichier d'évaluation trouvé (#{eval_file}). Création d'un exemple...")
      create_sample_training_data()
    end
  end
end
