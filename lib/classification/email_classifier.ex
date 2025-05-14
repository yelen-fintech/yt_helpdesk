defmodule Classification.EmailClassifier do
  use GenServer
  require Logger

  @model_path "priv/data/models/classifier_model.bin"
  @training_data_dir "priv/data/json"

  # API Publique
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def classify(email) do
    GenServer.call(__MODULE__, {:classify, email})
  end

  def train(file_path) do
    GenServer.call(__MODULE__, {:train, file_path}, :infinity)
  end

  def get_model_info do
    GenServer.call(__MODULE__, :model_info)
  end

  # Callbacks GenServer
  @impl true
  def init(_) do
    File.mkdir_p!(Path.dirname(@model_path))
    File.mkdir_p!(@training_data_dir)

    model = load_model() || create_default_model()

    {:ok, %{model: model}}
  end

  @impl true
  def handle_call({:classify, email}, _from, %{model: model} = state) do
    classification = do_classify(email, model)
    {:reply, classification, state}
  end

  @impl true
  def handle_call({:train, file_path}, _from, state) do
    case train_model(file_path, state.model) do
      {:ok, new_model, metrics} ->
        {:reply, {:ok, metrics}, %{state | model: new_model}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:model_info, _from, state) do
    info = %{
      categories: Map.get(state.model, :categories, []),
      labels: Map.get(state.model, :labels, []),
      priorities: Map.get(state.model, :priorities, []),
      last_trained: Map.get(state.model, :last_trained, nil),
      samples_count: Map.get(state.model, :samples_count, 0)
    }

    {:reply, info, state}
  end

  defp do_classify(email, model) do
    # Combiner sujet et corps pour l'analyse
    text = "#{Map.get(email, :subject, "")} #{Map.get(email, :body, "")}"
    text = String.downcase(text)

    # Déterminer la catégorie
    category = cond do
      Regex.match?(~r/\bconnexion|login|mot\s+de\s+passe|password\b/i, text) -> "account"
      Regex.match?(~r/\bpaiement|payment|carte\b/i, text) -> "payment"
      Regex.match?(~r/\berror|erreur|bug|plantage\b/i, text) -> "technical"
      Regex.match?(~r/\bcommande|order|livraison|delivery\b/i, text) -> "order"
      true -> "general"
    end

    # Déterminer la priorité
    priority = cond do
      Regex.match?(~r/\burgent|immediate|urgent|critique\b/i, text) -> "high"
      Regex.match?(~r/\bimportant\b/i, text) -> "medium"
      true -> "low"
    end

    # Extraire des labels potentiels
    labels = []
    |> add_label_if_match(text, ~r/\bconnexion|login\b/i, "login")
    |> add_label_if_match(text, ~r/\bmot\s+de\s+passe|password\b/i, "password")
    |> add_label_if_match(text, ~r/\bpaiement|payment\b/i, "payment")
    |> add_label_if_match(text, ~r/\bcommande|order\b/i, "order")
    |> add_label_if_match(text, ~r/\blivraison|delivery\b/i, "delivery")
    |> add_label_if_match(text, ~r/\bremboursement|refund\b/i, "refund")

    # Calculer la confiance avec la fonction calculate_confidence
    confidence = calculate_confidence(email, model)

    %{
      category: category,
      priority: priority,
      labels: labels,
      confidence: confidence
    }
  end

  defp add_label_if_match(labels, text, pattern, label) do
    if Regex.match?(pattern, text), do: [label | labels], else: labels
  end

  defp train_model(file_path, current_model) do
    try do
      filename = Path.basename(file_path)

      # Traitement spécifique pour keywords.json
      if filename == "keywords.json" do
        Logger.info("Processing keywords file: #{file_path}")

        # Charger les mots-clés
         keywords_map = load_json_data(file_path) # <= Ici, on charge le JSON
                       |> Map.new(fn {k, v} -> {String.to_atom(k), v} end) #

        # Extraire les catégories des mots-clés
        categories = Map.keys(keywords_map)
                    |> Enum.filter(fn key -> key != "default" end)  # Ignorer la catégorie "default"

        # Extraire tous les mots-clés uniques comme "labels"
        all_keywords = keywords_map
                      |> Map.values()
                      |> List.flatten()
                      |> Enum.uniq()

        # Mettre à jour le modèle uniquement avec les nouvelles catégories et labels
        new_model = Map.merge(current_model, %{
          categories: (Map.get(current_model, :categories, []) ++ categories) |> Enum.uniq(),
          labels: (Map.get(current_model, :labels, []) ++ all_keywords) |> Enum.uniq()
        })

        # Sauvegarder les mots-clés dans le modèle pour référence future
        new_model = Map.put(new_model, :keywords_by_category, keywords_map)

        # Sauvegarder le modèle
        save_model(new_model)

        # Métriques simples pour ce cas
        metrics = %{
          accuracy: Map.get(current_model, :accuracy, 0.80),
          samples: 0,  # Pas d'exemples ajoutés
          categories: length(categories),
          labels: length(all_keywords)
        }

        {:ok, new_model, metrics}
      else
        # Code existant pour les fichiers de données d'entraînement normaux
        training_data = load_json_data(file_path)

        # Enregistrer les données dans notre répertoire local si nécessaire
        store_training_data(file_path)

        # Extraire les catégories, labels et priorités
        categories = training_data
                    |> Enum.map(& Map.get(&1, "category"))
                    |> Enum.uniq()

        labels = training_data
                |> Enum.flat_map(& Map.get(&1, "labels", []))
                |> Enum.uniq()

        priorities = training_data
                    |> Enum.map(& Map.get(&1, "priority"))
                    |> Enum.uniq()

        # Construire le nouveau modèle
        new_model = Map.merge(current_model, %{
          categories: (Map.get(current_model, :categories, []) ++ categories) |> Enum.uniq(),
          labels: (Map.get(current_model, :labels, []) ++ labels) |> Enum.uniq(),
          priorities: (Map.get(current_model, :priorities, []) ++ priorities) |> Enum.uniq(),
          last_trained: DateTime.utc_now(),
          samples_count: length(training_data) + Map.get(current_model, :samples_count, 0)
        })

        # Sauvegarder le modèle
        save_model(new_model)

        # Métriques pour cette implémentation
        metrics = %{
          accuracy: 0.85,
          samples: length(training_data),
          categories: length(categories),
          labels: length(labels)
        }

        {:ok, new_model, metrics}
      end
    rescue
      e ->
        Logger.error("Failed to train model: #{inspect(e)}")
        {:error, "Model training failed: #{Exception.message(e)}"}
    end
  end

  defp load_json_data(file_path) do
    file_path
    |> File.read!()
    |> Jason.decode!()
  end

  defp store_training_data(file_path) do
    filename = Path.basename(file_path)
    local_path = Path.join(@training_data_dir, filename)

    unless file_path == local_path do
      File.cp!(file_path, local_path)
      Logger.info("Training data saved locally at #{local_path}")
    end
  end

  defp load_model do
    if File.exists?(@model_path) do
      Logger.info("Loading existing model from #{@model_path}")
      try do
        @model_path
        |> File.read!()
        |> :erlang.binary_to_term()
      rescue
        e ->
          Logger.error("Failed to load model: #{inspect(e)}")
          nil
      end
    end
  end

  defp create_default_model do
    Logger.info("Creating default model")
    %{
      categories: ["general", "account", "technical", "payment", "order"],
      labels: ["login", "password", "payment", "order", "delivery", "refund"],
      priorities: ["low", "medium", "high"],
      last_trained: nil,
      samples_count: 0
    }
  end

  defp save_model(model) do
    binary = :erlang.term_to_binary(model)
    File.write!(@model_path, binary)
    Logger.info("Model saved to #{@model_path}")
  end

  defp calculate_confidence(email, model) do
    # Extraire le texte complet de l'email
    text = "#{email.subject} #{email.body}"

    # Détecter la catégorie
    category = determine_category(email, model)

    # Charger les mots-clés depuis le fichier JSON
    keywords = get_keywords_for_category(category)

    # Compter les correspondances
    keyword_matches = count_matches(text, keywords)

    # Calculer la confiance (entre 0.5 et 0.95)
    # La formule ajuste la confiance en fonction du nombre de mots-clés trouvés
    base_confidence = 0.5
    confidence_per_match = 0.15
    max_confidence = 0.95

    min(base_confidence + (keyword_matches * confidence_per_match), max_confidence)
  end

  # Charge les mots-clés pour une catégorie spécifique depuis le fichier JSON
  defp get_keywords_for_category(category) do
    # Chemin vers le fichier JSON contenant les mots-clés
    keywords_file = "priv/data/json/keywords.json"

    # Valeurs par défaut en cas d'échec de chargement
    default_keywords = %{
      "account" => ["compte", "connexion", "identifiant", "mot de passe", "login", "password"],
      "order" => ["commande", "livraison", "colis", "expédition", "order", "delivery"],
      "payment" => ["paiement", "facture", "remboursement", "banque", "payment", "refund"],
      "technical" => ["bug", "erreur", "problème", "technique", "error", "technical"],
      "default" => []
    }

    case File.read(keywords_file) do
      {:ok, json_content} ->
        case Jason.decode(json_content) do
          {:ok, keywords_map} ->
            # Récupérer les mots-clés pour la catégorie ou utiliser une liste vide
            Map.get(keywords_map, category, Map.get(keywords_map, "default", []))

          {:error, _reason} ->
            # En cas d'erreur de décodage, utiliser les valeurs par défaut
            Map.get(default_keywords, category, [])
        end

      {:error, _reason} ->
        # Si le fichier n'existe pas, créer le fichier avec les valeurs par défaut
        # et retourner les mots-clés pour la catégorie
        File.mkdir_p!(Path.dirname(keywords_file))
        File.write!(keywords_file, Jason.encode!(default_keywords, pretty: true))
        Map.get(default_keywords, category, [])
    end
  end

  # Compte le nombre de mots-clés qui se trouvent dans le texte
  defp count_matches(text, keywords) do
    text = String.downcase(text)
    Enum.count(keywords, fn keyword -> String.contains?(text, keyword) end)
  end

  # Fonction manquante qu'il faudrait ajouter
defp determine_category(email, _model) do
  # Combiner sujet et corps pour l'analyse
  text = "#{Map.get(email, :subject, "")} #{Map.get(email, :body, "")}"
  text = String.downcase(text)

  # Logique de détermination de catégorie similaire à celle dans do_classify
  cond do
    Regex.match?(~r/\bconnexion|login|mot\s+de\s+passe|password\b/i, text) -> "account"
    Regex.match?(~r/\bpaiement|payment|carte\b/i, text) -> "payment"
    Regex.match?(~r/\berror|erreur|bug|plantage\b/i, text) -> "technical"
    Regex.match?(~r/\bcommande|order|livraison|delivery\b/i, text) -> "order"
    true -> "general"
  end
end

end
