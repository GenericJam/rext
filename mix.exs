defmodule Rext.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/genericjam/rext"

  def project do
    [
      app: :rext,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: "BEAM-on-desktop UI framework for Elixir (mob's desktop sibling)",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Rext.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.4", only: [:dev, :test], runtime: false},
      # ex_slop — Credo plugin catching AI-generated patterns (blanket rescue,
      # narrator docs, redundant Enum chains). Wired in .credo.exs.
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      # erlfmt formats the Erlang NIF stub in src/.
      {:erlfmt, "~> 1.8", only: :dev, runtime: false},
      # mix_audit — CVE scan over mix.lock. See CLAUDE.md for the app.start quirk.
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  # `mix setup` installs deps and activates the shared git hooks (.githooks):
  # format / credo --strict / compile run on every push, plus the suite when
  # mix.exs changes — the same gate CI enforces.
  defp aliases do
    [setup: ["deps.get", "cmd git config core.hooksPath .githooks"]]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"] ++ Path.wildcard("decisions/*.md"),
      groups_for_extras: [Decisions: Path.wildcard("decisions/*.md")]
    ]
  end
end
