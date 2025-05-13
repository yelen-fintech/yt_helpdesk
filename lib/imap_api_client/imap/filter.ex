# lib/imap_api_client/imap/filter.ex
defmodule ImapApiClient.Imap.Filter do
  @moduledoc """
  Module pour filtrer les emails IMAP.
  """

  require Logger
  alias ImapApiClient.Imap.Handler

  @type filter_options :: [
    client: atom(),
    filter: Yugo.Filter.t(),
    subject: String.t() | Regex.t(),
    from: String.t() | Regex.t(),
    has_flags: [atom()],
    lacks_flags: [atom()]
  ]

  @doc """
  Écoute les emails qui correspondent aux filtres spécifiés.
  """
  @spec listen(filter_options) :: :ok
  def listen(opts \\ []) do
    client = Keyword.get(opts, :client, :default_client)
    filter = build_filter(opts)

    do_listen(client, filter, opts)
  end

  @spec do_listen(atom(), Yugo.Filter.t(), Keyword.t()) :: :ok
  defp do_listen(client, filter, _opts) do
    Logger.info("Démarrage de l'écoute avec le filtre: #{inspect_filter(filter)}")

    Yugo.subscribe(client, filter)

    Logger.warning("ImapApiClient.Imap.Filter.listen/1 called, but EmailManager handles subscription via handle_info. This function might be redundant.")
    receive_loop() # Note: This loop will block the calling process indefinitely.
  end

  @spec receive_loop :: no_return
  defp receive_loop do
    receive do
      {:email, _client, message} ->
        Logger.info("Email filtré reçu: \"#{message.subject}\"")
        Handler.handle_message(message)
        receive_loop()

      other ->
        Logger.warning("Message non reconnu: #{inspect(other)}")
        receive_loop()
    end
  end


  @doc """
  Construit un filtre basé sur les options fournies.
  """
  @spec build_filter(filter_options) :: Yugo.Filter.t()
  def build_filter(opts) do
    # Commencer avec un filtre qui accepte tous les emails
    filter = opts |> Keyword.get(:filter, Yugo.Filter.all())

    # Appliquer les différents critères de filtre
    filter = case Keyword.get(opts, :subject) do
      subject when is_binary(subject) ->
        regex = Regex.compile!(".*#{Regex.escape(subject)}.*", "i")
        Yugo.Filter.subject_matches(filter, regex)
      %Regex{} = regex ->
        Yugo.Filter.subject_matches(filter, regex)
      nil ->
        filter
    end

    filter = case Keyword.get(opts, :from) do
      from when is_binary(from) ->
        regex = Regex.compile!(".*#{Regex.escape(from)}.*", "i")
        Yugo.Filter.sender_matches(filter, regex)
      %Regex{} = regex ->
        Yugo.Filter.sender_matches(filter, regex)
      nil ->
        filter
    end

    filter = case Keyword.get(opts, :has_flags) do
      flags when is_list(flags) and length(flags) > 0 ->
        Enum.reduce(flags, filter, fn flag, acc -> Yugo.Filter.has_flag(acc, flag) end)
      _ ->
        filter
    end

    filter = case Keyword.get(opts, :lacks_flags) do
      flags when is_list(flags) and length(flags) > 0 ->
        Enum.reduce(flags, filter, fn flag, acc -> Yugo.Filter.lacks_flag(acc, flag) end)
      _ ->
        filter
    end

    filter
  end

  @spec inspect_filter(Yugo.Filter.t()) :: String.t()
  defp inspect_filter(filter) do
    parts = []

    parts = if filter.subject_regex, do: ["sujet: #{inspect filter.subject_regex}" | parts], else: parts
    parts = if filter.sender_regex, do: ["expéditeur: #{inspect filter.sender_regex}" | parts], else: parts
    parts = if length(filter.has_flags) > 0, do: ["flags présents: #{inspect filter.has_flags}" | parts], else: parts
    parts = if length(filter.lacks_flags) > 0, do: ["flags absents: #{inspect filter.lacks_flags}" | parts], else: parts

    case parts do
      [] -> "Tout accepté"
      parts -> Enum.join(parts, ", ")
    end
  end
end
