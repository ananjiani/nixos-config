---
name: elisp
description: Use when writing or editing Emacs Lisp — doom config, packages.el, init.el, config.el, or any .el file. Run agent-lisp-paren-aid after every elisp edit to catch unbalanced parens you cannot reliably self-verify. Trigger phrases include "emacs lisp", "elisp", "doom config", "config.el", "init.el", "packages.el", "use-package", "defun", "setq".
---

# Emacs Lisp

Writing or editing `.el` files in this repo (doom config under `modules/home/editors/doom-emacs/`).

## The one rule: don't count parens yourself

LLMs write elisp with correct indentation but **miscount closing parens** — too few is the common failure, too many happens too. You cannot reliably balance them by eye. Don't try.

**After every elisp edit, run the checker:**

```bash
agent-lisp-paren-aid <file.el>
```

It runs the file through Emacs' own re-indenter and reports the first line where parens break:

| Output | Meaning |
|---|---|
| `ok` | Balanced. Done. |
| `Error: line N: There are extra M closing parentheses.` | Too many — remove `)` around line N |
| `Error: line N: Missing M closing parentheses.` | Too few — add `)` at/after line N |

## Workflow

1. Edit the `.el` file.
2. Run `agent-lisp-paren-aid <file>`.
3. If not `ok`: fix **only** the reported line, re-run. Don't batch other edits until it's `ok` — a misreport cascades.
4. Only `ok` → continue with other work.

## Why not count manually

Indentation looks right even when parens are wrong — that's the whole class of bug this catches. The tool uses Emacs itself to re-indent, so the failure line is exact. Trust the tool's line number over your own paren counting, every time.

## Prerequisite

`agent-lisp-paren-aid` needs Emacs on PATH (it shells out to `emacs` for re-indentation analysis). Emacs is installed system-wide on all workstations in this repo. If the binary is missing, the package wasn't built — check `modules/home/dev/pi-coding-agent.nix`.
