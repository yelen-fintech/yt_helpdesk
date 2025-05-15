defmodule MailClassifier do
  @moduledoc """
  Module principal pour classifier des emails.
  """

  @doc """
  Classifie un email et renvoie la catégorie la plus probable.

  ## Exemples

      iex> MailClassifier.classify("Bonjour, j'espère que vous allez bien. Pouvons-nous planifier une réunion?")
      %{category: "professionnel", scores: [...]}

  """
  def classify(email_text) do
    ImapApiClient.Classifier.Model.classify_email(email_text)
  end

  @doc """
  Classifie une liste d'emails et renvoie leurs catégories respectives.
  """
  def classify_batch(emails) when is_list(emails) do
    Enum.map(emails, &classify/1)
  end
end
