---
name: repo-tools
description: Use when the user wants to explore, read, analyze, or ingest a git repository from any host (GitHub, GitLab, Codeberg, Gitea, self-hosted, or local). This includes understanding a foreign codebase, reviewing a dependency, checking upstream changes, or extracting code context for AI analysis. Do NOT wait for permission — proactively ingest repos when they are relevant to the task.
---

# Repo Tools

Two bash commands on PATH for working with git repositories. No MCPs — just call these directly via the `bash` tool.

## When to use each

| Task | Tool |
|---|---|
| "Pack this repo for analysis" / "Read this codebase" / "Summarize this project" | `repo-ingest` |
| "List files in this repo" / "Read a specific file" / "Search this repo" / "What's in directory X?" | `repo-browse` |

Both work with **any git host**: GitHub, GitLab, Codeberg, Gitea, Forgejo, self-hosted instances, or local paths. They shallow-clone remote repos on demand and cache them for the session.

---

## repo-ingest

Packs an entire repository (or a subset) into a single AI-friendly plain-text dump. Wraps `repomix`.

```bash
repo-ingest <git-url|local-path> [--include <glob>] [--compress]
```

**Examples:**

```bash
# Full public repo
repo-ingest https://github.com/yamadashy/repomix

# Only the src/ directory
repo-ingest https://github.com/yamadashy/repomix --include "src/**"

# With tree-sitter compression (~70% token reduction)
repo-ingest https://codeberg.org/forgejo/forgejo --compress

# Local repo
repo-ingest ./my-project --include "**/*.nix"
```

**When to use:**
- You need broad understanding of a codebase (architecture, patterns, structure)
- The user asks you to "review", "summarize", "refactor", or "learn" a repo
- The repo is small enough to fit in context (or you're using `--include` to narrow scope)

**When NOT to use:**
- The repo is massive (nixpkgs, linux kernel) and you only need one file — use `repo-browse cat`
- You need a live file listing first to decide what to read — use `repo-browse ls` or `repo-browse tree`

---

## repo-browse

Targeted exploration without packing the entire repo. Shallow-clones with `--depth 1` and caches in `/tmp/repo-browse-cache/` for the session.

```bash
repo-browse ls   <git-url> [path]      # list directory contents
repo-browse cat  <git-url> <path>      # read a specific file
repo-browse grep <git-url> <pattern>   # search file contents
repo-browse tree <git-url> [path]      # show full directory tree
```

**Examples:**

```bash
# See what's in the top level
repo-browse ls https://github.com/nixos/nixpkgs

# Read a specific file
repo-browse cat https://github.com/nixos/nixpkgs pkgs/top-level/all-packages.nix

# Search for a function or pattern
repo-browse grep https://codeberg.org/forgejo/forgejo "func InitWeb"

# See directory structure
repo-browse tree https://github.com/yamadashy/repomix src
```

**When to use:**
- The repo is huge and you'd waste tokens ingesting everything
- You need to find where something lives before reading it
- You only need one or two files
- You're doing targeted research (e.g., "how does X handle Y?")

---

## Decision flow

1. **User asks about a repo** → `repo-browse tree <url>` first to see structure
2. **Need broad understanding / review / refactor** → `repo-ingest <url>`
3. **Repo is huge or scope is narrow** → `repo-browse cat` / `repo-browse grep` specific files
4. **Need to compare two repos** → `repo-ingest` both, or `repo-browse` targeted files
5. **Private repo** → Both tools work via SSH if your key is loaded. For HTTPS, standard git credential helpers apply.

---

## Interaction with web-tools

| Situation | Use |
|---|---|
| GitHub/GitLab/Codeberg **web page** (README rendered in browser, issues, PRs) | `web-fetch` or `web-fetch-jina` |
| Git repository **source code** (files, directories, git history) | `repo-ingest` or `repo-browse` |

Do not use `web-fetch` on `github.com/user/repo` — it returns HTML, not the source code. Use `repo-browse` or `repo-ingest` instead.
