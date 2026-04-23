---
name: gh
description: Use the GitHub CLI (gh) for authenticated GitHub operations — repos, issues, pull requests, releases, actions, and API queries. Load when the user mentions GitHub, gh, or working with GitHub repos.
---

# GitHub CLI (`gh`)

Use `gh` for authenticated GitHub operations from the terminal. Prefer explicit, idempotent commands and report URLs back to the user.

## Quick checks

```bash
gh auth status                          # verify auth
gh repo view --json nameWithOwner,url   # current repo context
```

## Core workflows

### Repositories

```bash
gh repo create OWNER/NAME --private --description "..."
gh repo clone OWNER/NAME
gh repo fork OWNER/NAME --clone
gh repo view OWNER/NAME --web
gh repo delete OWNER/NAME --yes         # destructive — confirm first
gh repo sync OWNER/NAME                 # sync a fork
```

### Issues

```bash
gh issue list --limit 20
gh issue create --title "..." --body "..."
gh issue view <num>
gh issue comment <num> --body "..."
gh issue close <num>
gh issue reopen <num>
gh issue edit <num> --title "..." --body "..."
```

### Pull requests

```bash
gh pr create --title "..." --body "..." [--base main] [--head branch]
gh pr list --limit 20
gh pr view <num>
gh pr view <num> --web
gh pr diff <num>
gh pr merge <num> --merge|--squash|--rebase
gh pr checkout <num>
gh pr close <num>
gh pr review <num> --approve|--request-changes --body "..."
```

### CI / Actions

```bash
gh run list --limit 10
gh run view <run-id>
gh run view <run-id> --log-failed       # failed steps only
gh run rerun <run-id>
gh workflow list
gh workflow run <workflow> [--ref branch]
gh workflow enable <workflow>
gh workflow disable <workflow>
```

### Releases

```bash
gh release create vX.Y.Z --title "vX.Y.Z" --notes "..."
gh release list
gh release download vX.Y.Z
gh release view vX.Y.Z
```

### Raw API

```bash
gh api repos/owner/repo/pulls/55 --jq '.title, .state, .user.login'
gh api graphql -f query='query { ... }'
```

## JSON output

Most commands support `--json` with `--jq` for structured output:

```bash
gh issue list --json number,title --jq '.[] | "\(.number): \(.title)"'
gh pr list --json number,title,headRefName
```

## Safety

- Confirm the target repo/owner before destructive actions (delete, force push).
- For private repos, ensure `--private` is set on create.
- Prefer `--yes` or `--confirm` to avoid interactive prompts in automation.
