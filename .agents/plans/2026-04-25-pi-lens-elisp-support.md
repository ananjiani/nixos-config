# Add Emacs Lisp support to pi-lens

**Date**: 2026-04-24 (planned)
**Status**: Planned
**Goal**: Extend pi-lens to detect elisp parenthesis errors in real-time when agents edit `.el` files, by forking pi-lens and adding an `emacs --batch -f batch-byte-compile` dispatch runner.

## Problem

AI agents (pi) frequently produce malformed elisp with mismatched or incorrectly-nested parentheses. pi-lens hooks into pi's write/edit events and runs language-aware linting — but it has no elisp support. `emacs --batch -f batch-byte-compile` already catches paren errors with line numbers and exits non-zero on failure. Wiring this into pi-lens would give real-time inline feedback.

## Alternative approaches considered

| Approach | Why not |
|---|---|
| AGENTS.md instruction to run `emacs --batch` manually | Relies on agent remembering; no automatic feedback |
| MCP server (elisp-dev-mcp, emacs-mcp-server, anvil.el) | pi does not support MCP |
| Custom pi extension wrapping `emacs --batch` | Rebuilds half of pi-lens's dispatch pipeline; pi-lens already does this better |
| agent-lisp-paren-aid (Go binary) | Another dependency; `emacs --batch` already does the same thing |
| Upstream PR to pi-lens | Should do this eventually, but fork first to unblock immediately |

## Plan

- [ ] **Fork `apmantza/pi-lens`** to `ananjiani/pi-lens` on Codeberg (or GitHub)
- [ ] **Add `"elisp"` FileKind** in `clients/file-kinds.ts`
  - Add `"elisp"` to the `FileKind` union type
  - Add `elisp: [".el"]` to `KIND_EXTENSIONS`
  - Add `"elisp"` to `SUPPORTED_FILE_KINDS` array
  - Add `"elisp"` to `isCodeKind()` return list
  - Add `elisp: "Emacs Lisp"` to `getFileKindLabel()` labels
  - Add `elisp: "emacs-lisp"` to `getLanguageId()` language IDs
- [ ] **Add elisp project markers** in `clients/language-profile.ts`
  - Add `elisp: ["init.el", "config.el"]` to `PROJECT_MARKERS_BY_KIND`
  - Add `elisp: ["init.el", ".dir-locals.el"]` to `ROOT_MARKERS_BY_KIND`
- [ ] **Add elisp language policy** in `clients/language-policy.ts`
  - Add `elisp: { lspCapable: false }` to `LANGUAGE_POLICY`
  - Add dispatch group to `PRIMARY_DISPATCH_GROUPS`:
    ```
    elisp: { mode: "fallback", runnerIds: ["emacs-byte-compile"], filterKinds: ["elisp"] }
    ```
- [ ] **Write `emacs-byte-compile` dispatch runner** in `clients/dispatch/runners/emacs-byte-compile.ts`
  - Model on `shellcheck.ts` (~80 lines)
  - `appliesTo: ["elisp"]`
  - `run()`: execute `emacs --batch -f batch-byte-compile <file>`
  - Parse stderr for error lines like `file.el:3:1: Error: End of file during parsing`
  - Map to `Diagnostic` objects with `severity: "error"`, `semantic: "blocking"`
  - Exit code 0 = clean, return empty diagnostics
  - Check `emacs` is available via `which`; skip if not found
- [ ] **Register the runner** in `clients/dispatch/runners/index.ts`
  - Import `emacsByteCompileRunner`
  - Add `registry.register(emacsByteCompileRunner)` in `registerDefaultRunners()`
- [ ] **Optionally add emacs indent formatter** in `clients/formatters.ts`
  - Use `emacs --batch --eval '(progn (find-file "$FILE") (indent-region (point-min) (point-max)) (save-buffer))'`
  - Only if we want auto-formatting, not required for paren validation
- [ ] **Install from fork**:
  ```bash
  pi install git:github.com/ananjiani/pi-lens
  ```
- [ ] **Test the integration**:
  - Run pi in the doom-emacs config directory
  - Have the agent edit `config.el` with a deliberate mismatched paren
  - Verify pi-lens shows a blocking diagnostic with the correct line number
  - Verify clean edits produce no diagnostics
- [ ] **Upstream PR**: Open a PR against `apmantza/pi-lens` with the changes
  - Small, well-scoped (~100 lines) following an established pattern
  - Eliminates the need to maintain a fork

## Files touched (in fork)

| File | Nature of change |
|---|---|
| `clients/file-kinds.ts` | Add `elisp` FileKind + extension mapping |
| `clients/language-profile.ts` | Add project/root markers |
| `clients/language-policy.ts` | Add language policy + dispatch group |
| `clients/dispatch/runners/emacs-byte-compile.ts` | **New file** — the runner (~80 lines) |
| `clients/dispatch/runners/index.ts` | Register the runner (2 lines) |
| `clients/formatters.ts` | Optional — emacs indent formatter |

## Dependencies

- `emacs` on PATH (already available on this system — NixOS-managed `emacs-pgtk-30.2`)
- pi-lens fork (npm package)
