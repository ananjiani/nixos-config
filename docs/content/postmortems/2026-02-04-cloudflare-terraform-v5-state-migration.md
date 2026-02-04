---
date: 2026-02-04
title: Cloudflare Terraform provider v5 broke all DNS resource management
severity: minor
duration: 0h 30m
systems: [terraform, cloudflare, dns]
tags: [terraform, provider-upgrade, dns, state-migration]
commit:
---

## Summary

After updating the Cloudflare Terraform provider from v4 to v5 (`~> 5.0`), `tofu plan` failed on all 19 DNS records with "Invalid resource type" errors. The v5 provider renamed `cloudflare_record` to `cloudflare_dns_record` and cannot read v4 state schema at all. Required removing all 20 entries from state and re-importing them under the new resource type. No actual DNS records were affected — this was purely a state and config issue.

## Timeline

- **~Earlier** - Updated Cloudflare provider constraint from v4 to `~> 5.0` in `providers.tf`, ran `tofu init` to pull v5.16.0
- **~Shortly after** - Ran `tofu plan`, hit 19 "Invalid resource type" errors for every `cloudflare_record` resource
- **Investigation** - Confirmed via provider docs and community reports that v5 is a ground-up rewrite with renamed resources
- **Migration** - Extracted record IDs from state, removed all 20 `cloudflare_record.*` entries, renamed resources in config to `cloudflare_dns_record`, re-imported all 19 active records
- **Verified** - `tofu plan` shows zero DNS drift, all records correctly tracked under new resource type

## What Happened

The Cloudflare Terraform provider v5 is a complete rewrite auto-generated from Cloudflare's OpenAPI schema. This isn't a typical semver-major bump with a few deprecations — the entire provider was regenerated, and many resource types were renamed to be more specific (`cloudflare_record` became `cloudflare_dns_record`).

The provider constraint was updated to `~> 5.0` and `tofu init` pulled v5.16.0 without issue. But `tofu plan` immediately failed because the v5 provider's schema registry doesn't include `cloudflare_record` at all. OpenTofu couldn't even read the existing state entries — it wasn't a config-only problem but a state deserialization failure.

The fix required a three-step process: (1) extract all record IDs from the current state before it became unreadable, (2) `tofu state rm` all old entries, (3) re-import each record under the new `cloudflare_dns_record` type using the `zone_id/record_id` format. An orphaned `scriberr` record in state (no longer in config) was cleaned up in the process.

Additionally, the `hostname` computed attribute was removed in v5 — outputs referencing `.hostname` needed to change to `.name`.

## Contributing Factors

- The Cloudflare v5 provider is a fundamentally different kind of major version bump — not just breaking API changes, but a full provider rewrite with renamed resource types
- No migration path exists within OpenTofu itself — `moved` blocks don't work because the v5 provider can't deserialize v4 state (schema_version mismatch)
- Cloudflare's official Grit-based migration tool has known bugs (GitHub issue #5044) and doesn't handle all cases
- The `~> 5.0` constraint was applied without checking the upgrade guide for breaking changes first

## What I Was Wrong About

- **"Major version bumps just change some attributes"** — This wasn't a normal v4→v5. The provider was regenerated from scratch, so resource type names changed entirely. The mental model of "update constraint, fix a few deprecation warnings" didn't apply.
- **"OpenTofu state is resilient to provider upgrades"** — The state format is tightly coupled to the provider's schema registry. If the provider drops a resource type entirely, the state becomes unreadable for those entries. There's no graceful fallback.

## What Helped

- OpenTofu state was local, so `state pull` and `state rm` worked without remote backend complications
- `tofu state pull` could still parse the full JSON state file even though `tofu plan` couldn't — this let us extract all record IDs before removing anything
- The actual DNS records in Cloudflare were completely unaffected by the state manipulation — state rm doesn't delete real resources
- All the attribute names (`zone_id`, `name`, `content`, `type`, `proxied`, `ttl`, `comment`) stayed the same between v4 and v5, so the config changes were purely mechanical renames

## What Could Have Been Worse

- If this had been run in CI with auto-apply, and if OpenTofu had somehow interpreted the missing resource type as "these resources should be destroyed," all 19 DNS records could have been deleted
- If the state had been remote (e.g., S3 backend) with locking issues, the state rm + import cycle would have been more complex
- If attribute names had also changed (not just the resource type), each record would have needed config changes beyond a simple find-and-replace

## Is This a Pattern?

- [x] One-off: Correct and move on
- [ ] Pattern: Revisit the approach

This is specific to Cloudflare's unusual decision to auto-generate their v5 provider from OpenAPI schemas, which caused wholesale resource renames. Most Terraform providers don't do this. However, the lesson about reading upgrade guides before bumping major versions applies broadly.

## Action Items

- [ ] Check if any other Cloudflare resource types used in the codebase were renamed in v5 (currently only DNS records are used, but worth verifying if more are added)
- [ ] Pin Renovate to not auto-bump Terraform provider major versions without manual review (if not already configured)

## Lessons

- Cloudflare's Terraform provider v5 is not a normal major version bump — it's a complete provider rewrite. Always read the upgrade guide before updating: https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/guides/version-5-upgrade
- `tofu state rm` is safe for resources that exist in the upstream API — it only makes Terraform "forget" about them, it doesn't destroy them
- The import format for v5 DNS records is `zone_id/record_id`, not just `record_id`
- When migrating renamed resources: extract IDs first, state rm, update config, then re-import. Don't try `moved` blocks across provider rewrites.
