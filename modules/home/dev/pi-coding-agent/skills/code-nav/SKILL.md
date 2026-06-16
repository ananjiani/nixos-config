---
name: code-nav
description: Use for structural code search — finding definitions, references, calls, or code that matches a syntactic shape. Reach for this when plain text search (rg) would give false positives or miss things that are structurally equivalent but textually different. Trigger phrases include "find all definitions of", "where is X called", "find every function that", "structural search", "AST search".
---

# Code Navigation

`ast-grep` is on PATH. It searches code using tree-sitter grammars, so it understands syntax — a `def foo` matches only a function definition, not a comment or string containing "def foo".

## When to use which

| Task | Tool |
|---|---|
| Literal string, fuzzy text, filenames | `rg` (default — don't reach for ast-grep) |
| Find a definition by name/shape | `ast-grep` |
| Find references or call sites | `ast-grep` |
| Match structural patterns ("every method that calls super") | `ast-grep` |
| Rename across files | do edits normally; ast-grep only to *find* the targets first |

If a query is just "where does the string `webFetch` appear", use `rg`. If it's "where is `webFetch` defined as a binding", ast-grep avoids matching mentions in comments or prose.

## Invocation

```bash
ast-grep run -l <lang> -p '<pattern>' [path...]
```

- `run` — one-time search (default subcommand)
- `-l <lang>` — language grammar: `python`, `typescript`, `tsx`, `javascript`, `go`, `rust`, `html`, `css`, `yaml`, `json`, `nix`, and [more](https://ast-grep.github.io/reference/languages.html)
- `-p '<pattern>'` — the structural pattern
- `path` — file or dir, defaults to cwd

Add `--json=compact` for machine-readable output when you want to post-process matches.

## Pattern syntax (metas)

| Meta | Meaning |
|---|---|
| `$NAME` | match and capture a single node (identifier, literal, etc.) |
| `$$` | match any single node, unnamed (use for "something here") |
| `$$$` | match multiple nodes (use for "anything, including nothing") |

Named captures (`$NAME`) show up in output. `$$$` is how you say "and whatever else" in the middle of a pattern.

**Patterns are structural, not regex.** `def $NAME($$$): $$$` is a function definition; the `:` and parens are real syntax, not literal text to grep.

## Per-language cheatsheet

### Python

```bash
# function definitions
ast-grep run -l python -p 'def $NAME($$$): $$$'
# specific function by name
ast-grep run -l python -p 'def my_func($$$): $$$'
# class definitions
ast-grep run -l python -p 'class $NAME($$$): $$$'
# imports
ast-grep run -l python -p 'import $NAME'
ast-grep run -l python -p 'from $MOD import $$$'
# method calls on an object
ast-grep run -l python -p '$OBJ.$METHOD($$$)'
```

### TypeScript / tsx / JavaScript

```bash
# function declarations
ast-grep run -l typescript -p 'function $NAME($$$) {$$$}'
# const arrow functions
ast-grep run -l typescript -p 'const $NAME = ($$$) => $$$'
# interface/type definitions
ast-grep run -l typescript -p 'interface $NAME $$$'
ast-grep run -l typescript -p 'type $NAME = $$$'
# exported anything
ast-grep run -l typescript -p 'export $$$'
# React components (tsx) — use -l tsx
ast-grep run -l tsx -p 'function $NAME($$$) {$$$}'
```

### Go

```bash
# function definitions
ast-grep run -l go -p 'func $NAME($$$) $$$'
# methods (receiver)
ast-grep run -l go -p 'func ($$$) $NAME($$$) $$$'
# type declarations
ast-grep run -l go -p 'type $NAME $$$'
# struct types
ast-grep run -l go -p 'type $NAME struct $$$'
```

### Rust

```bash
# functions
ast-grep run -l rust -p 'fn $NAME($$$) $$$'
# impl blocks
ast-grep run -l rust -p 'impl $$$ {$$$}'
# enum / struct definitions
ast-grep run -l rust -p 'enum $NAME $$$'
ast-grep run -l rust -p 'struct $NAME $$$'
```

### YAML / JSON

```bash
# k8s resource kinds
ast-grep run -l yaml -p 'kind: $$$'
# a specific key
ast-grep run -l yaml -p 'apiVersion: $$$'
```

## Limitations

ast-grep is **syntactic, not semantic**. It matches on grammar structure, not on what symbols resolve to. So:

- Two functions named `handle` in different classes both match `def handle($$$): $$$` — ast-grep can't tell them apart.
- A call `foo.bar()` matches the pattern, but ast-grep won't tell you *which* `bar` it resolves to.
- No import-aware "find all callers of this specific function across the codebase."

For pure structural queries (definitions, references, call shapes) this is exactly what you want. If you need true semantic resolution — disambiguating which method, following imports, type-aware renames — that's LSP territory, not this tool.

## Tips

- **First time on a new grammar?** `ast-grep run -l <lang> -p '<simple pattern>' --debug=ast` prints the tree-sitter nodes so you can see what the grammar calls things. Useful when a pattern doesn't match what you expect.
- **Restrict to a path:** pass the directory as the last arg. `ast-grep run -l python -p '...' src/` only searches `src/`.
- **Combine with rg:** use ast-grep to find definitions, rg to grep within those files for usage. They compose fine.
