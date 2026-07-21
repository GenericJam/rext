defmodule Mix.Tasks.Erlfmt do
  @moduledoc """
  Format `.erl` files (or check formatting with `--check`).

  Wraps `erlfmt`'s library API. Exists because the upstream `erlfmt` Hex package
  ships an escript build but no `mix` task; the pre-commit checklist (`CLAUDE.md`)
  references `mix erlfmt --check src/`, so this task makes that instruction work.

  Ported verbatim from mob — rext has one Erlang source (`src/rext_nif.erl`), the
  NIF stub, and it gets held to the same formatting gate as everything else.

  ## Usage

      mix erlfmt --check src/         # exit 0 if clean, exit 1 if any file would change
      mix erlfmt --write src/         # rewrite files in place
  """

  use Mix.Task

  @shortdoc "Format Erlang sources via erlfmt"

  @impl Mix.Task
  def run(args) do
    {opts, paths} =
      OptionParser.parse!(args,
        strict: [check: :boolean, write: :boolean],
        aliases: [c: :check, w: :write]
      )

    if !opts[:check] and !opts[:write] do
      Mix.raise("mix erlfmt requires --check or --write")
    end

    if paths == [], do: Mix.raise("mix erlfmt requires at least one path")

    unless Code.ensure_loaded?(:erlfmt) do
      Mix.raise(
        "mix erlfmt requires the `:erlfmt` dep — add `{:erlfmt, \"~> 1.8\", " <>
          "only: :dev, runtime: false}` to your project's mix.exs and rerun `mix deps.get`."
      )
    end

    Application.ensure_all_started(:erlfmt)

    files = Enum.flat_map(paths, &collect_erl_files/1)

    {ok_count, changed} =
      Enum.reduce(files, {0, []}, fn file, {ok, changed} ->
        case apply(:erlfmt, :format_file, [String.to_charlist(file), [:return]]) do
          {:ok, formatted, _warnings} ->
            original = File.read!(file)
            # erlfmt returns iodata that may include codepoints > 255 (em-dashes
            # in comments etc); :unicode.characters_to_binary handles those where
            # IO.iodata_to_binary would crash.
            new = :unicode.characters_to_binary(formatted)

            cond do
              new == original ->
                {ok + 1, changed}

              opts[:write] ->
                File.write!(file, new)
                Mix.shell().info("formatted #{file}")
                {ok + 1, changed}

              true ->
                {ok, [file | changed]}
            end

          {:skip, _} ->
            {ok + 1, changed}

          {:error, reason} ->
            Mix.shell().error("#{file}: #{inspect(reason)}")
            {ok, [file | changed]}
        end
      end)

    cond do
      changed == [] ->
        Mix.shell().info("erlfmt: #{ok_count} file(s) checked, all formatted")
        :ok

      opts[:check] ->
        Mix.shell().error(
          "erlfmt: #{length(changed)} file(s) need formatting:\n  " <>
            Enum.join(changed, "\n  ") <>
            "\n\nRun `mix erlfmt --write <path>` to fix."
        )

        exit({:shutdown, 1})

      true ->
        :ok
    end
  end

  defp collect_erl_files(path) do
    cond do
      File.dir?(path) -> Path.wildcard("#{path}/**/*.erl")
      File.regular?(path) and String.ends_with?(path, ".erl") -> [path]
      true -> []
    end
  end
end
