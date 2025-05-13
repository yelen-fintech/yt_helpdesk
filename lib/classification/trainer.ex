defmodule Classification.ModelTrainer do
  @moduledoc """
  Module pour faciliter l'entraînement et la validation du modèle
  de classification d'emails en utilisant des ensembles de données.
  """

  alias Classification.EmailClassifier
  require Logger

  @training_data_dir "priv/data/json"

  @doc """
  Entraîne le modèle avec tous les fichiers JSON disponibles dans
  le répertoire d'entraînement.

  Retourne un récapitulatif des métriques d'entraînement.
  """
  def train_all do
    # S'assurer que le répertoire existe
    File.mkdir_p!(@training_data_dir)

    # Trouver tous les fichiers JSON dans le répertoire
    files = Path.wildcard("#{@training_data_dir}/*.json")

    if Enum.empty?(files) do
      Logger.warning("Aucun fichier d'entraînement trouvé dans #{@training_data_dir}")
      {:error, :no_training_files}
    else
      # Entraîner avec chaque fichier
      results = Enum.map(files, fn file ->
        Logger.info("Entraînement avec #{file}")
        case EmailClassifier.train(file) do
          {:ok, metrics} -> {Path.basename(file), metrics}
          {:error, reason} -> {Path.basename(file), {:error, reason}}
        end
      end)

      # Compter les succès et les échecs
      {successes, failures} = results
                              |> Enum.split_with(fn {_, result} ->
                                  not match?({:error, _}, result)
                              end)

      # Construire le résumé
      summary = %{
        total_files: length(files),
        successful: length(successes),
        failed: length(failures),
        failures: failures,
        metrics: extract_combined_metrics(successes)
      }

      {:ok, summary}
    end
  end

  @doc """
  Crée un ensemble de données d'entraînement à partir des emails fournis.

  ## Paramètres
  - `emails` - Liste d'emails à utiliser pour créer les données
  - `manual_classifications` - Map associant des identifiants d'email à leur classification
  - `file_name` - Nom du fichier de sortie (optionnel, par défaut généré avec timestamp)

  ## Exemple
    ```
    emails = [%{id: "1", subject: "Problème connexion", body: "..."}, ...]
    manual_classifications = %{
      "1" => %{category: "account", priority: "high", labels: ["login"]}
    }
    ModelTrainer.create_training_data(emails, manual_classifications)
    ```
  """
  def create_training_data(emails, manual_classifications, file_name \\ nil) do
    # Générer un nom de fichier par défaut si non fourni
    file_name = file_name || "training_data_#{DateTime.utc_now() |> DateTime.to_unix()}.json"
    file_path = Path.join(@training_data_dir, file_name)

    # Créer le répertoire si nécessaire
    File.mkdir_p!(@training_data_dir)

    # Transformer les emails en données d'entraînement
    training_data = emails
                    |> Enum.filter(fn email -> Map.has_key?(manual_classifications, email.id) end)
                    |> Enum.map(fn email ->
                        classification = Map.get(manual_classifications, email.id)
                        %{
                          "subject" => email.subject,
                          "body" => email.body,
                          "category" => classification.category,
                          "priority" => classification.priority,
                          "labels" => classification.labels
                        }
                    end)

    # Écrire dans un fichier JSON
    case Jason.encode(training_data, pretty: true) do
      {:ok, json} ->
        File.write!(file_path, json)
        Logger.info("Données d'entraînement enregistrées dans #{file_path}")
        {:ok, %{file_path: file_path, samples: length(training_data)}}

      {:error, reason} ->
        Logger.error("Erreur lors de l'encodage JSON: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Évalue la performance du modèle actuel sur un ensemble de test.

  ## Paramètres
  - `test_data` - Fichier JSON contenant les données de test

  Retourne des métriques d'évaluation.
  """
  def evaluate(test_data_path) do
    try do
      # Charger les données de test
      test_data =
        test_data_path
        |> File.read!()
        |> Jason.decode!()

      # Évaluer chaque exemple
      results = Enum.map(test_data, fn sample ->
        # Préparer l'email pour la classification
        email = %{
          subject: Map.get(sample, "subject", ""),
          body: Map.get(sample, "body", "")
        }

        # Obtenir la prédiction
        prediction = EmailClassifier.classify(email)

        # Comparer avec la vérité terrain
        expected_category = Map.get(sample, "category")
        expected_priority = Map.get(sample, "priority")
        expected_labels = MapSet.new(Map.get(sample, "labels", []))

        # Calculer les métriques pour cet exemple
        category_correct = prediction.category == expected_category
        priority_correct = prediction.priority == expected_priority

        # Pour les labels, calculer precision et recall
        predicted_labels = MapSet.new(prediction.labels)
        true_positives = MapSet.size(MapSet.intersection(predicted_labels, expected_labels))
        false_positives = MapSet.size(MapSet.difference(predicted_labels, expected_labels))
        false_negatives = MapSet.size(MapSet.difference(expected_labels, predicted_labels))

        %{
          category_correct: category_correct,
          priority_correct: priority_correct,
          true_positives: true_positives,
          false_positives: false_positives,
          false_negatives: false_negatives
        }
      end)

      # Agréger les résultats
      total = length(results)
      category_accuracy = results |> Enum.count(& &1.category_correct) |> percentage(total)
      priority_accuracy = results |> Enum.count(& &1.priority_correct) |> percentage(total)

      # Calculer precision et recall globaux pour les labels
      total_tp = results |> Enum.map(& &1.true_positives) |> Enum.sum()
      total_fp = results |> Enum.map(& &1.false_positives) |> Enum.sum()
      total_fn = results |> Enum.map(& &1.false_negatives) |> Enum.sum()

      precision = percentage(total_tp, total_tp + total_fp)
      recall = percentage(total_tp, total_tp + total_fn)
      f1_score = if precision + recall > 0, do: 2 * precision * recall / (precision + recall), else: 0

      # Retourner les métriques complètes
      metrics = %{
        samples: total,
        category_accuracy: category_accuracy,
        priority_accuracy: priority_accuracy,
        labels_precision: precision,
        labels_recall: recall,
        labels_f1: f1_score
      }

      {:ok, metrics}
    rescue
      e ->
        Logger.error("Erreur lors de l'évaluation: #{inspect(e)}")
        {:error, "Échec de l'évaluation: #{Exception.message(e)}"}
    end
  end

  # Fonctions privées

  defp percentage(part, total) when total > 0, do: part * 100 / total
  defp percentage(_, _), do: 0

  defp extract_combined_metrics(results) do
    # Extraire les métriques moyennes des résultats réussis
    metrics_list = results
                  |> Enum.map(fn {_, metrics} -> metrics end)

    if Enum.empty?(metrics_list) do
      %{samples: 0}
    else
      # Calculer les moyennes - correction de la syntaxe du pipeline
      %{
        samples: metrics_list |> Enum.map(& &1.samples) |> Enum.sum(),
        # Utiliser des parenthèses pour regrouper correctement l'opération de division
        accuracy: (metrics_list |> Enum.map(& &1.accuracy) |> Enum.sum()) / length(metrics_list),
        categories: metrics_list |> Enum.map(& &1.categories) |> Enum.max(fn -> 0 end),
        labels: metrics_list |> Enum.map(& &1.labels) |> Enum.max(fn -> 0 end)
      }
    end
  end

end
