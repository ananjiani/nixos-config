---
date: 2026-01-25
title: SOPS-encrypted k8s secret fails Flux decryption due to slash in IV
severity: moderate
duration: 2h 30m
systems: [flux, sops, kubernetes]
tags: [kubernetes, sops, flux, encryption, gitops]
commit: https://codeberg.org/ananjiani/infra/commit/0b7e258
---

## Summary

A newly added Kubernetes secret encrypted with SOPS failed to decrypt in Flux with a cryptic "does not match sops' data format" error. The secret decrypted fine locally. Other identically-structured secrets worked. The issue was that base64-encoded IVs in encrypted metadata fields contained `/` characters that Flux interpreted as path separators.

## Timeline

All times in CST.

- **15:28** - Pushed forgejo-runner deployment with SOPS-encrypted secret
- **15:35** - Noticed Flux apps kustomization stuck with decryption error
- **15:40** - Verified secret decrypts locally with `sops -d`
- **16:00** - Compared with other working secrets - identical structure
- **16:30** - Noticed error message showed malformed path with fragments like `.el1TOHYw=,tag:`
- **16:45** - Identified the fragment as part of an IV containing `/` character
- **17:00** - Applied fix: `encrypted_regex: '^(data|stringData)$'` in .sops.yaml
- **17:05** - Re-encrypted secret, pushed, Flux applied successfully

## What Happened

Added a Forgejo Actions runner to the k8s cluster with a SOPS-encrypted secret containing the runner registration. Flux's kustomize-controller failed to decrypt it with:

```
error decrypting sops tree: Error walking tree: Could not decrypt value:
Input string <redacted> does not match sops' data format
```

The error message included garbled encrypted strings that looked like multiple `ENC[...]` blocks concatenated with dots. Running `sops -d` locally worked perfectly.

Compared with other working secrets in the same repo - they had the same encryption pattern (apiVersion, kind, metadata all encrypted). The only difference was the specific encrypted values.

Examining the error more closely revealed fragments like `.el1TOHYw=,tag:VKh2kZ3NVOXnrApIx/hAzQ==` appearing in the middle of resource paths. This matched part of the `apiVersion` field's IV: `iv:z8WryoSm9BhYJMAKVRJ0W3IdaMYc7b7ZNJ/el1TOHYw=`. The `/` in the IV was being interpreted as a path separator.

## Contributing Factors

- **SOPS encrypts entire YAML by default**: Without `encrypted_regex`, SOPS encrypts all fields including `apiVersion`, `kind`, and `metadata`
- **Base64 encoding uses `/` character**: The base64 alphabet includes `/`, which has ~1.5% probability per character
- **IVs are ~32 base64 characters**: ~40% chance any given encrypted field will have a `/` in its IV
- **Flux constructs resource paths from metadata**: When metadata fields are encrypted, Flux uses the encrypted strings to build paths like `namespace/name`
- **No validation of path characters**: Flux doesn't escape or validate the characters in encrypted field values before using them in paths

## What I Was Wrong About

- **"Same encryption pattern means same behavior"**: I assumed that because other secrets had the same structure (all fields encrypted), they would behave identically. The randomness of IVs means two identically-structured secrets can have different failure modes.

- **"Local decryption success means Flux will succeed"**: SOPS itself can decrypt fine regardless of IV contents. The failure is in how Flux processes the encrypted YAML before passing it to SOPS.

## What Helped

- **Detailed error messages**: Although confusing at first, the error included the actual encrypted strings, which allowed identifying the `/` in the IV
- **Comparison with working secrets**: Having other SOPS-encrypted secrets that worked helped narrow down that this was secret-specific, not a key or configuration issue
- **Local sops -d worked**: Confirmed the encryption itself was valid, pointing to a Flux-specific issue

## What Could Have Been Worse

- **This could have silently affected existing secrets on rotation**: If an existing working secret was re-encrypted and happened to get a `/` in a new IV, it would break on the next Flux reconciliation with no code changes
- **Could have taken much longer to diagnose**: If I hadn't noticed the fragmented path structure in the error, might have spent hours on key configuration

## Is This a Pattern?

- [x] Pattern: Revisit the approach

The default SOPS behavior of encrypting everything is incompatible with Flux's resource path construction. This will affect any new secret with ~40% probability, and any re-encryption of existing secrets.

**What needs to change**: Always use `encrypted_regex: '^(data|stringData)$'` for Kubernetes secrets with SOPS + Flux. This is actually the recommended pattern in Flux documentation, but the default SOPS behavior makes it easy to miss.

## Action Items

- [x] Add `encrypted_regex: '^(data|stringData)$'` to .sops.yaml for k8s secrets path
- [ ] Re-encrypt all existing k8s secrets to use the new format (for consistency and to prevent future rotation issues)
- [ ] Document this in repo's CLAUDE.md for future reference

## Lessons

- **SOPS + Flux requires `encrypted_regex` for k8s secrets**: The default "encrypt everything" behavior is subtly incompatible with Flux
- **Random components in encryption can cause intermittent failures**: Just because something worked before doesn't mean the same operation will work again
- **When error messages look garbled, the garbling itself may be the clue**: The malformed path fragments directly pointed to the IV issue
- **"Works locally" doesn't mean "works in the pipeline"**: Different tools process the same encrypted file differently
