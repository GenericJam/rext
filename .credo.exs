%{
  configs: [
    %{
      name: "default",
      # ex_slop is a credo PLUGIN (registers its whole check bundle), not a
      # check — listing it under checks.enabled is silently ignored.
      plugins: [{ExSlop, []}],
      files: %{
        included: ["lib/", "test/", "src/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      checks: %{
        enabled: [
          {Credo.Check.Readability.Specs, files: %{excluded: ["test/"]}},
          {Credo.Check.Refactor.UnlessWithElse, []},
          # jump_credo_checks
          {Jump.CredoChecks.AvoidFunctionLevelElse, []},
          {Jump.CredoChecks.AvoidLoggerConfigureInTest, []},
          {Jump.CredoChecks.TestHasNoAssertions, []},
          {Jump.CredoChecks.TooManyAssertions, []},
          {Jump.CredoChecks.TopLevelAliasImportRequire, []},
          {Jump.CredoChecks.WeakAssertion, []},
          {Jump.CredoChecks.VacuousTest, []}
        ],
        disabled: [
          # Pipes with single function calls are fine in this codebase.
          {Credo.Check.Readability.SinglePipe, []}
        ]
      }
    }
  ]
}
