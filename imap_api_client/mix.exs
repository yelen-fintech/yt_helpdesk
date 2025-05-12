defmodule ImapApiClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :imap_api_client,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ImapApiClient.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:hackney, "~> 1.9"},
      {:yugo, "~> 1.0"},
      {:swoosh, "~> 1.9"},
      {:gen_smtp, "~> 1.2"},
      {:httpoison, "~> 2.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
