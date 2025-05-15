defmodule ImapApiClient.Classifier.Model do
  use GenServer
  require Logger

  # Catégories pour la classification des emails
  @categories ["spam", "promotions_marketing", "personnel", "professionnel_interne", "support_client", "demande_information_question", "feedback_suggestion", "documentation"]

  # Niveaux d'urgence
  @urgency_levels ["low", "medium", "high"]

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("Chargement du modèle DistilBERT multilingual...")

    # Chargement du modèle pré-entraîné pour la classification
    # Note : Ce modèle n'est PAS fine-tuné sur VOS catégories ou l'urgence.
    # La classification réelle est simulée dans handle_call/3 et simulate_classification/1.
    # Pour une utilisation en production, vous devriez fine-tuner ce modèle
    # ou en entraîner un spécifiquement pour VOS tâches (catégorie et urgence).
    {:ok, model_info} = Bumblebee.load_model({:hf, "distilbert-base-multilingual-cased"},
      architecture: :for_sequence_classification)
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "distilbert-base-multilingual-cased"})

    # Création du pipeline de classification de texte (utilisé ici principalement pour l'encodage/tokenisation)
    # Si vous aviez 2 modèles fine-tunés, vous créeriez 2 serving ici.
    # La variable 'serving' est conservée dans l'état mais n'est plus utilisée
    # dans handle_call/3 dans la logique de simulation.
    serving = Bumblebee.Text.text_classification(model_info, tokenizer,
      defn_options: [compiler: EXLA] # Compiler pour la performance si EXLA est dispo
    )

    Logger.info("Modèle chargé avec succès!")

    {:ok, %{serving: serving}}
  end

  @doc """
  Classifie un email et renvoie la catégorie et le niveau d'urgence les plus probables.
  """
  def classify_email(email_text) do
    GenServer.call(__MODULE__, {:classify, email_text}, 30_000)
  end

  @impl true
  # On préfixe 'serving' par '_' car on ne l'utilise pas dans le corps de cette fonction
  def handle_call({:classify, email_text}, _from, %{serving: _serving} = state) do
    # Dans un cas réel avec un modèle fine-tuné:
    # 1. Envoyer l'email_text au(x) modèle(s) fine-tuné(s).
    # 2. Obtenir les scores réels pour les catégories et l'urgence.

    # Ici, on utilise le serving (qui utilise le modèle de base) juste pour simuler
    # le passage du texte dans un pipeline. On ne se base PAS sur sa prédiction.
    # Le résultat de ce serving n'est pas directement utilisé pour nos catégories/urgence.
    # result_from_base_model = Nx.Serving.run(_serving, email_text) # Exemple si on l'utilisait

    # À la place, on simule directement la prédiction pour nos catégories et urgence.
    # Si vous aviez 2 servings (un pour cat, un pour urgence), vous les appelleriez ici.
    # Par exemple:
    # category_prediction = Nx.Serving.run(category_serving, email_text)
    # urgency_prediction = Nx.Serving.run(urgency_serving, email_text)

    # Simulation des scores pour les catégories et l'urgence.
    # Cette fonction simule le résultat que vous obtiendriez d'un modèle fine-tuné
    # sur vos données avec vos labels.
    simulated_results = simulate_classification_and_urgency(email_text)


    {:reply, simulated_results, state}
  end

  # Simulateur pour la catégorie ET l'urgence
  # ATTENTION: Cette fonction est purement illustrative et NE reflète PAS la
  # performance d'un vrai modèle fine-tuné. Elle génère des scores fictifs.
  defp simulate_classification_and_urgency(email_text) do
    # --- Simulation de la prédiction de Catégorie ---
    # Logique de simulation arbitraire basée sur le texte pour distribuer des scores
    # Ceci est JUSTE une simulation pour montrer la structure de sortie.
    # Un vrai modèle utiliserait les poids appris pendant l'entraînement.
    text_hash_for_cat = :erlang.phash2(email_text)
    num_categories = length(@categories)
    # Choisir une catégorie "gagnante" basée sur le hash
    winning_cat_index = rem(text_hash_for_cat, num_categories)
    # On préfixe par '_' car la variable n'est pas utilisée après cette ligne
    _winning_category = Enum.at(@categories, winning_cat_index)

    category_scores = @categories
    |> Enum.with_index()
    |> Enum.map(fn {category, idx} ->
      # Assigner un score élevé à la catégorie "gagnante" simulée
      # et distribuer le reste aux autres.
      score = if idx == winning_cat_index, do: 0.8 + :rand.uniform() * 0.1, else: (0.2 / (num_categories - 1)) * :rand.uniform()
      {category, Float.round(score, 4)}
    end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)

    predicted_category = elem(hd(category_scores), 0)

    # --- Simulation de la prédiction d'Urgence ---
    # Logique de simulation arbitraire basée sur le texte (ou une autre partie du hash)
    # Ceci est JUSTE une simulation.
    text_hash_for_urgency = :erlang.phash2(email_text, 2) # Utiliser un autre hash ou seed
    num_urgency_levels = length(@urgency_levels)
    # Choisir un niveau d'urgence "gagnant" basé sur le hash
    winning_urgency_index = rem(text_hash_for_urgency, num_urgency_levels)
     # On préfixe par '_' car la variable n'est pas utilisée après cette ligne
    _winning_urgency = Enum.at(@urgency_levels, winning_urgency_index)

    urgency_scores = @urgency_levels
    |> Enum.with_index()
    |> Enum.map(fn {level, idx} ->
       # Assigner un score élevé au niveau "gagnant" simulé
       score = if idx == winning_urgency_index, do: 0.7 + :rand.uniform() * 0.2, else: (0.3 / (num_urgency_levels - 1)) * :rand.uniform()
       {level, Float.round(score, 4)}
    end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)

    predicted_urgency = elem(hd(urgency_scores), 0)


    # --- Résultat simulé final ---
    %{
      predicted_category: predicted_category,
      category_scores: category_scores,
      predicted_urgency: predicted_urgency,
      urgency_scores: urgency_scores
      # original_prediction: nil # Le modèle de base n'est pas pertinent ici
    }
  end
end
