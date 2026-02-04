---
date: 2026-01-31
title: CLIProxy lost all provider configs and API keys on pod restart
severity: moderate
duration: 1h 30m
systems: [k3s, cliproxy, flux]
tags: [kubernetes, persistence, emptydir, configmap]
commit: https://codeberg.org/ananjiani/infra/commit/5a547bc
---

## Summary

CLIProxy (CLI Proxy API) lost all provider configurations, model aliases, and a manually-added API key whenever the pod restarted. The management panel showed empty provider sections despite auth token files surviving on the PVC. Resolved by moving all runtime-modified config into the ConfigMap with secret injection via the init container.

## Timeline

- **~07:00 CST** - User noticed CLIProxy configs missing after a pod restart
- **07:15** - Investigation began; confirmed auth JSON files survived on PVC but management panel showed no providers
- **07:30** - Identified that running config.yaml had `oauth-model-alias` and provider sections not present in the ConfigMap template
- **07:35** - Realized config.yaml lives on an `emptyDir`, rebuilt from ConfigMap by init container on every restart, wiping runtime additions
- **07:45** - Added `oauth-model-alias` section and kimi-key placeholder to ConfigMap; updated init container sed to inject both secrets
- **08:00** - First commit pushed; Flux apps kustomization stuck on unrelated codeberg-runner health check failure
- **08:15** - Corrected kimi-key placement from top-level `api-keys` to `claude-api-key` provider section
- **08:28** - Manually applied ConfigMap and restarted pod; confirmed full config present and working

## What Happened

CLIProxy stores its configuration in `/CLIProxyAPI/config.yaml`. The Kubernetes deployment used an init container to inject an API key from a SOPS secret into a ConfigMap template, writing the result to an `emptyDir` volume. The main container then mounted this file.

The problem: when users added provider configurations (model aliases, upstream API keys, additional providers) through the management panel, the app wrote those changes to config.yaml. Since config.yaml lived on an emptyDir, all those additions vanished on pod restart.

The auth token files (Claude and Codex OAuth tokens) survived on a Longhorn PVC, but these are just cached tokens - separate from the provider configurations that tell the app which upstream services to use. The management panel correctly showed the auth files section populated but the provider configuration sections empty.

The fix was straightforward: capture the full desired config (including `oauth-model-alias`, `claude-api-key` provider config) into the ConfigMap, with secret values replaced by placeholders that the init container injects via `sed`.

An additional wrinkle: the kimi-key was initially placed in the top-level `api-keys` list (client authentication to the proxy) when it actually belonged in the `claude-api-key` section (upstream provider configuration). These serve fundamentally different purposes.

## Contributing Factors

- The `emptyDir` volume for config.yaml was an inherent fragility - any runtime modification to the file would be lost
- The ConfigMap only contained a minimal template, not the full desired config
- No documentation or comments indicated that the management panel writes to config.yaml and those changes need to be captured back to the ConfigMap
- The distinction between client auth keys (`api-keys`) and upstream provider keys (`claude-api-key`) wasn't obvious without reading the full example config

## What I Was Wrong About

- **"Auth files on PVC = configs persist"** - The auth JSON files and the provider configurations are separate concerns. The auth files are OAuth token storage; the provider configs (which providers to use, base URLs, model mappings) live in config.yaml.
- **"The management panel is just a viewer"** - It's actually a writer. Changes made through the panel modify config.yaml at runtime, making it stateful.
- **"emptyDir is fine for derived config"** - Only if the config is truly derived and never modified at runtime. CLIProxy's config.yaml is both an input (initial settings) and an output (runtime modifications).

## What Helped

- Being able to `kubectl exec` into the pod and `cat` the running config.yaml immediately showed what was present at runtime vs what was in the ConfigMap
- The CLIProxy example config (`config.example.yaml`) at 200+ lines documented every possible section, making it clear what the full config structure looks like
- Hot-reload support meant we could verify changes without restarting the pod (though the underlying issue was about restart behavior)

## What Could Have Been Worse

- If the Longhorn PVC had also been lost, the OAuth tokens would have needed re-authentication through the browser-based OAuth flow, which requires SSH tunneling for headless servers
- The `oauth-model-alias` section had 7 model mappings - without the running pod to inspect, reconstructing these from memory would have been error-prone

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

Any app that writes runtime state to config files will have this problem when config is injected via ConfigMap + emptyDir. This pattern appears in other services too. The general rule: if an app modifies its own config file, either mount the config on a PVC or ensure the ConfigMap contains the complete desired state.

## Action Items

- [x] Move `oauth-model-alias` into ConfigMap
- [x] Move kimi-key to `claude-api-key` provider section in ConfigMap
- [x] Update init container to inject all secrets
- [ ] Audit other k8s apps for the same emptyDir config pattern where the app writes to its own config
- [ ] Pin cliproxy image to a specific version tag instead of `latest`

## Lessons

- In Kubernetes, `emptyDir` is ephemeral by design. If an app writes to a file on an emptyDir, those writes are gone on restart. This is obvious in hindsight but easy to overlook when the config "looks fine" during normal operation.
- Management panels that modify config files create hidden state. The source of truth shifts from "what's in git" to "what's running in the pod" without any visible signal.
- When debugging "configs disappeared," check both the config file AND any separate state files. Auth tokens, provider configs, and API keys may all live in different places.
