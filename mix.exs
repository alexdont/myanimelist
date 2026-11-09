defmodule MyAnimeList.MixProject do
  use Mix.Project

  @version "0.2.0"
  @description "MyAnimeList API v2 client for Elixir, covering both anime and manga: public search & metadata, the OAuth (PKCE) login flow, and authenticated list sync. Errors as values, a Req.Test seam, and a TokenStore behaviour so persistence stays in your app (no Ecto dependency)."
  @source_url "https://github.com/alexdont/myanimelist"

  def project do
    [
      app: :myanimelist,
      version: @version,
      description: @description,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:req, "~> 0.4 or ~> 0.5 or ~> 0.6"},
      {:plug, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "myanimelist",
      maintainers: ["Alexander Don"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      name: "MyAnimeList",
      source_ref: "v#{@version}",
      source_url: @source_url,
      main: "MyAnimeList",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
