defmodule Classification.EmailClassifierTest do
  use ExUnit.Case
  alias Classification.EmailClassifier

  setup do
    # Créer un fichier de test temporaire avec des données d'entraînement
    test_data = [
      %{
        "subject" => "Problème de connexion",
        "body" => "Je n'arrive pas à me connecter à mon compte",
        "category" => "account",
        "priority" => "high",
        "labels" => ["login"]
      },
      %{
        "subject" => "Commande en retard",
        "body" => "Ma livraison n'est pas arrivée",
        "category" => "order",
        "priority" => "medium",
        "labels" => ["delivery", "order"]
      }
    ]

    test_file = "priv/data/json/test_data_#{:rand.uniform(10000)}.json"
    File.mkdir_p!(Path.dirname(test_file))
    File.write!(test_file, Jason.encode!(test_data))

    # Démarrer le classificateur si pas encore démarré
    # (normalement géré par l'Application)
    start_supervised(EmailClassifier)

    # Fournir le fichier de test pour le teardown
    on_exit(fn -> File.rm(test_file) end)
    %{test_file: test_file}
  end

  describe "classify/1" do
    test "classifies an account-related email correctly" do
      email = %{
        subject: "Problème de connexion",
        body: "Je n'arrive pas à me connecter à mon compte"
      }

      result = EmailClassifier.classify(email)
      assert result.category == "account"
      assert result.priority == "high"
      assert "login" in result.labels
    end

    test "classifies an order-related email correctly" do
      email = %{
        subject: "Où est ma commande?",
        body: "J'ai passé commande il y a une semaine et la livraison n'est pas arrivée"
      }

      result = EmailClassifier.classify(email)
      assert result.category == "order"
      assert "order" in result.labels
      assert "delivery" in result.labels
    end

    test "classifies a payment-related email correctly" do
      email = %{
        subject: "Problème de paiement",
        body: "Je n'arrive pas à utiliser ma carte de crédit pour payer"
      }

      result = EmailClassifier.classify(email)
      assert result.category == "payment"
      assert "payment" in result.labels
    end
  end

  describe "train/1" do
    test "trains the model with new data", %{test_file: test_file} do
      # Vérifier l'état initial
      initial_info = EmailClassifier.get_model_info()

      # Entraîner avec le fichier de test
      {:ok, metrics} = EmailClassifier.train(test_file)

      # Vérifier les métriques
      assert is_map(metrics)
      assert Map.has_key?(metrics, :accuracy)
      assert Map.has_key?(metrics, :samples)

      # Vérifier que le modèle a été mis à jour
      updated_info = EmailClassifier.get_model_info()
      assert updated_info.last_trained != initial_info.last_trained
    end

    test "returns error with invalid data" do
      # Créer un fichier JSON invalide
      invalid_file = "priv/data/json/invalid_data.json"
      File.write!(invalid_file, "{not valid json")

      # Cleanup
      on_exit(fn -> File.rm(invalid_file) end)

      # Tester la gestion d'erreur
      result = EmailClassifier.train(invalid_file)
      assert match?({:error, _}, result)
    end
  end

  describe "get_model_info/0" do
    test "returns current model information" do
      info = EmailClassifier.get_model_info()

      # Vérifier que les clés requises sont présentes
      assert is_map(info)
      assert Map.has_key?(info, :categories)
      assert Map.has_key?(info, :labels)
      assert Map.has_key?(info, :priorities)
      assert Map.has_key?(info, :last_trained)
      assert Map.has_key?(info, :samples_count)

      # Vérifier que les catégories par défaut sont présentes
      assert "general" in info.categories
      assert "account" in info.categories
      assert "technical" in info.categories
    end
  end
end
