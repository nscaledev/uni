# Agent instruction synchronisation

The shared section of each configured repository's `AGENTS.md` is maintained in
[`shared.md`](shared.md). Content outside that section remains owned by the
target repository.

## Target configuration

Targets are configured in [`targets.json`](targets.json):

```json
{
  "targets": [
    {
      "repository": "nscaledev/example",
      "files": {
        "agents": "AGENTS.md",
        "claude": "CLAUDE.md"
      }
    }
  ]
}
```

An empty `targets` array is valid and makes the workflow a no-op.

The initial list was seeded from active `nscaledev` repositories with the
`unikorn` GitHub topic. It is intentionally explicit; topic changes do not alter
the sync scope automatically.

Each target is an object so target-specific options, such as shared overrides,
can be added later without changing the overall structure. Only `repository`,
`files.agents`, and `files.claude` are currently supported.

Specification links in `shared.md` follow the latest `uni-specifications/main`
content. Agents are required to stop without making changes if the applicable
documents cannot be retrieved.

## Synchronisation behaviour

The sync script replaces content between these exact markers:

```markdown
<!-- BEGIN UNI SHARED INSTRUCTIONS -->
<!-- END UNI SHARED INSTRUCTIONS -->
```

The script follows these rules:

- If `AGENTS.md` is missing, it creates the managed section and an empty
  repository-specific section.
- If `AGENTS.md` exists without markers, the managed section is prepended and
  all existing content is preserved as repository-specific guidance.
- If either marker is already present, the file must contain exactly one
  correctly ordered pair. Partial, duplicate, or reversed markers cause the
  script to fail without changing the file.
- Content outside the markers is preserved.
- If `CLAUDE.md` is missing, it is created with an import of the configured
  `AGENTS.md`.
- If `CLAUDE.md` exists, the import is prepended only when it is missing.
- A `CLAUDE.md` symlink to the configured `AGENTS.md` is also accepted.

Run the script against a checked-out repository with:

```shell
scripts/sync-agent-instructions.sh \
  agent-instructions/shared.md \
  /path/to/repository \
  AGENTS.md \
  CLAUDE.md
```

The configured `AGENTS.md` and `CLAUDE.md` must be in the same directory. This
keeps the Claude import portable and unambiguous.

Run the Bash fixture tests with:

```shell
scripts/test-sync-agent-instructions.sh
```

## GitHub Actions

The sync workflow runs after relevant changes reach `main`, or when dispatched
manually. It updates a fixed `repo-sync/agent-instructions` branch and creates or
updates a pull request only when a target repository changes.

The workflow uses the organisation's existing GitHub App credentials:

- `NSCALE_ACTIONS_APP_ID` repository variable
- `NSCALE_ACTIONS_APP_PK` repository secret

It creates a short-lived token for each target repository with only repository
contents and pull-request write permissions. The GitHub App must be installed on
every configured target repository.
