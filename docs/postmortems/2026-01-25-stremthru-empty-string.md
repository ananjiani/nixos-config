---
date: 2026-01-25
title: Comet addon broken by empty STREMTHRU_URL environment variable
severity: major
duration: ~45m
systems: [stremio, comet, torbox]
tags: [streaming, configuration, environment-variables]
commit: https://codeberg.org/ananjiani/infra/commit/51ddebd
supersedes: 2026-01-25-1439-stremio-4k-buffering
---

## Summary

Comet addon failed to stream any content, showing "Failed to check account status /v0/store/user?client_ip=" error. Root cause: setting `STREMTHRU_URL: ""` (empty string) caused Comet to use StremThru code paths instead of direct Torbox API calls. The `/v0/store/user` endpoint is a StremThru endpoint that doesn't exist on Torbox's API.

This postmortem supersedes [2026-01-25-1439-stremio-4k-buffering](2026-01-25-1439-stremio-4k-buffering.md), which incorrectly identified StremThru as the cause of buffering issues and recommended "disabling" it by setting the URL to empty string.

## Timeline

- **Earlier today** - 4K buffering issue investigated, incorrectly attributed to StremThru middleware
- **Earlier today** - Set `STREMTHRU_URL: ""` thinking this would disable StremThru
- **~16:00** - User reported Torbox showing "Failed to check account status" error on all content
- **~16:10** - Verified Torbox API key was valid (200 OK from `/v1/api/user/me`)
- **~16:15** - Noticed error path `/v0/store/user` - this is a StremThru endpoint format, not Torbox
- **~16:20** - Tested official Torbox addon directly - worked fine, confirming issue was Comet-specific
- **~16:25** - Checked git history, found `STREMTHRU_URL: ""` was added in earlier "fix"
- **~16:30** - Removed `STREMTHRU_URL` environment variable entirely
- **~16:35** - Deployed fix, confirmed Comet working

## What Happened

In a previous debugging session, 4K buffering was incorrectly attributed to StremThru middleware. The "fix" was to set `STREMTHRU_URL: ""` to "disable" StremThru.

However, in Comet's code, an empty string is not the same as an unset variable:
- **Unset/missing**: Comet uses direct Torbox API (`/v1/api/...`)
- **Empty string `""`**: Comet detects the variable exists and enters StremThru code path, making requests to `/v0/store/user` (a StremThru endpoint)

The `/v0/store/user` endpoint doesn't exist on Torbox's API, causing all stream requests to fail with "Failed to check account status".

## The Actual Fix

Remove the environment variable entirely:

```yaml
# WRONG - enables StremThru code paths
- name: STREMTHRU_URL
  value: ""

# RIGHT - just don't include the variable at all
# (no STREMTHRU_URL entry)
```

## What Was Wrong About the Previous Postmortem

The [previous postmortem](2026-01-25-1439-stremio-4k-buffering.md) made several incorrect conclusions:

1. **"StremThru was causing buffering"** - StremThru was never in the path. The original config had no `STREMTHRU_URL` at all.

2. **"Setting STREMTHRU_URL to empty disables it"** - The opposite is true. Empty string activates StremThru code paths.

3. **"The fix was disabling StremThru"** - The fix was actually the **increased Comet resources** (memory/CPU limits) that were applied in the same commit. The `STREMTHRU_URL: ""` change was inert at best, harmful at worst.

## Contributing Factors

- **Untested assumption**: Assumed empty string = disabled, didn't verify Comet's behavior
- **Bundled changes**: Resource increases and STREMTHRU_URL change were in the same commit, making it unclear which actually helped
- **Confirmation bias**: Buffering stopped, so assumed the StremThru theory was correct
- **No immediate symptoms**: The `STREMTHRU_URL: ""` didn't break anything immediately (possibly cached state or different code path initially)

## What I Was Wrong About

- **"Empty string disables a feature"** - Common assumption, but application-specific. Some apps treat empty string as "use default", others as "feature enabled but misconfigured"
- **"StremThru was in the video path"** - It never was. The original working config had no StremThru configuration at all
- **"The investigation was thorough"** - Jumped to conclusions without verifying the actual fix

## Lessons

- **Empty string != unset**: When "disabling" a feature via environment variable, verify whether the app expects the variable to be absent vs empty. Test both cases.
- **Isolate changes**: Don't bundle unrelated fixes in the same commit. If resource changes and config changes are applied together, you can't know which helped.
- **Verify the fix, not the symptom**: "It stopped buffering" doesn't mean the diagnosis was correct. Could be coincidence, caching, or a different change that actually helped.
- **Check git history when debugging**: Today's fix came from checking what changed - `git log --oneline -p -- k8s/apps/stremio/` immediately revealed the problematic change.

## Action Items

- [x] Remove `STREMTHRU_URL` environment variable entirely
- [x] Update previous postmortem with superseded notice
- [ ] Add comment in deployment explaining why STREMTHRU_URL should not be set (even to empty)
