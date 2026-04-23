---
name: tea
description: Use the Gitea/Forgejo CLI (tea) for Codeberg operations — repos, issues, pull requests, labels, releases, CI runs, and API queries. Load when the user mentions Codeberg, Forgejo, Gitea, tea, or working with Codeberg repos.
---

# Codeberg/Forgejo CLI (`tea`)

Use `tea` for authenticated Codeberg/Forgejo operations from the terminal. Codeberg runs Forgejo (a Gitea fork) — `tea` is the official Gitea CLI and fully compatible. Prefer explicit, idempotent commands and report URLs back to the user.

## Auth setup

```bash
tea login add --name codeberg --url https://codeberg.org --token <personal-access-token>
tea login list                                # verify configured instances
tea login default codeberg                    # set default
```

Generate a token at **Codeberg → Settings → Applications**.

## Quick checks

```bash
tea whoami                                    # verify auth
tea repos info                                # current repo context
```

## Core workflows

### Repositories

```bash
tea repo create OWNER/NAME --private --description "..."
tea repo clone OWNER/NAME
tea repo fork OWNER/NAME
tea repo view OWNER/NAME
tea repo delete OWNER/NAME                    # destructive — confirm first
tea repo list                                 # your repos
```

### Issues

```bash
tea issues list --repo OWNER/REPO
tea issue create --repo OWNER/REPO --title "..." --body "..."
tea issue view <num> --repo OWNER/REPO
tea issue comment <num> --repo OWNER/REPO --body "..."
tea issue close <num> --repo OWNER/REPO
tea issue reopen <num> --repo OWNER/REPO
tea issue edit <num> --repo OWNER/REPO --title "..." --body "..."
```

### Pull requests

```bash
tea pr list --repo OWNER/REPO
tea pr create --repo OWNER/REPO --title "..." --body "..." --head branch --base main
tea pr view <num> --repo OWNER/REPO
tea pr diff <num> --repo OWNER/REPO
tea pr merge <num> --repo OWNER/REPO
tea pr close <num> --repo OWNER/REPO
tea pr review <num> --repo OWNER/REPO --approve|--request-changes --body "..."
```

### Labels

```bash
tea label list --repo OWNER/REPO
tea label create --repo OWNER/REPO --name "..." --color "#hex"
tea label delete <id> --repo OWNER/REPO
```

### Milestones

```bash
tea milestone list --repo OWNER/REPO
tea milestone create --repo OWNER/REPO --title "..."
tea milestone view <num> --repo OWNER/REPO
```

### Releases

```bash
tea release create --repo OWNER/REPO --tag vX.Y.Z --title "vX.Y.Z" --note "..."
tea release list --repo OWNER/REPO
tea release delete <tag> --repo OWNER/REPO
```

### CI / Actions

```bash
tea actions list --repo OWNER/REPO
tea actions runs list --repo OWNER/REPO
tea actions runs view <run-id> --repo OWNER/REPO
tea actions logs <run-id> --repo OWNER/REPO
tea actions secrets list --repo OWNER/REPO
tea actions variables list --repo OWNER/REPO
```

### Raw API

```bash
tea api repos/OWNER/REPO/pulls/55
tea api repos/OWNER/REPO/issues?state=open&limit=10
```

Use `tea api` for anything not covered by a subcommand — it hits the Forgejo REST API directly.

## Multiple logins

`tea` supports multiple Forgejo instances simultaneously. Select with `--login <name>`:

```bash
tea repo list --login codeberg
tea issue list --login myforgejo --repo OWNER/REPO
```

Set a default to avoid repeating `--login`:

```bash
tea login default codeberg
```

## Specifying the repo

- Inside a git clone of the repo: `tea` auto-detects from the remote.
- Outside a clone: add `--repo OWNER/REPO` to every command.
- For Codeberg specifically, ensure the remote URL uses `codeberg.org`.

## Repo conventions for this dotfiles repo

- **Codeberg is primary** (`codeberg.org/ananjiani/infra`)
- **GitHub is a push mirror** — do not create issues/PRs on GitHub
- Use `tea` (not `gh`) for Codeberg operations
- Use `gh repo sync` only for pushing the mirror

## Safety

- Confirm the target repo/owner before destructive actions (delete, force push).
- For private repos, ensure `--private` is set on create.
- Prefer non-interactive flags to avoid hanging on prompts.
