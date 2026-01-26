---
date: 2026-01-25
title: Stremio 4K buffering due to proxy misconfiguration and unnecessary middleware
severity: minor
duration: ~30m (investigation)
systems: [stremio, comet, torbox]
tags: [streaming, proxy, networking, performance]
commit: https://codeberg.org/ananjiani/infra/commit/9fcd23c
superseded_by: 2026-01-25-stremthru-empty-string
---

> **SUPERSEDED**: This postmortem contains an incorrect root cause analysis. The "fix" of setting `STREMTHRU_URL: ""` actually caused a subsequent outage. See [2026-01-25-stremthru-empty-string](2026-01-25-stremthru-empty-string.md) for the correction. The actual fix for the original buffering issue was likely the increased Comet resources, not the StremThru change.

## Summary

4K HDR content on Stremio (Android TV) was buffering despite fast internet. Investigation led down several paths before identifying the actual culprit: StremThru middleware adding an unnecessary hop. Fixed by disabling StremThru - the comet proxy setting ended up back where it started.

## Timeline

All times in CST.

- **13:10** - User reported buffering issues on 4K Stremio content
- **13:12** - Checked stremio pods - all healthy, low resource usage
- **13:15** - Checked comet logs - saw rapid stream connect/disconnect cycles
- **13:18** - Identified comet proxy was enabled, causing double-proxy through cluster
- **13:20** - Disabled comet proxy, assuming stremio-server would handle proxying
- **13:25** - Still buffering - stremio-server wasn't actually proxying video
- **13:28** - User confirmed: "downloading from Torbox dashboard is fast"
- **13:30** - User noted: "Netflix/Prime 4K works fine on same WiFi"
- **13:32** - Identified StremThru middleware in the path, adding another hop
- **13:35** - Key insight: Netflix uses adaptive bitrate, Torbox MKVs are fixed bitrate
- **13:38** - Re-enabled comet proxy, disabled StremThru, increased resources
- **13:42** - Deployed changes, confirmed working

## What Happened

The Stremio setup has several components:
- **Comet**: Stremio addon that finds streams from Torbox (debrid service)
- **Stremio-server**: Handles transcoding, subtitles, and can proxy streams
- **StremThru**: Third-party middleware between comet and Torbox

Initial assumption was that `PROXY_DEBRID_STREAM=True` on comet was causing double-proxying:
```
Torbox → Comet (proxy) → Stremio-server (proxy) → Android TV
```

So we disabled comet's proxy. But stremio-server wasn't actually proxying video - it only handles subtitle lookups and transcoding requests. With comet proxy disabled, the path became:
```
Torbox → Android TV (direct, over WiFi to internet)
```

This should have been fine, but buffering continued. User confirmed Torbox downloads were fast from their computer, and Netflix/Prime 4K worked fine on the same Android TV.

The key insight: **Netflix/Prime use adaptive bitrate streaming (HLS/DASH)** - they dynamically adjust quality based on available bandwidth. A momentary WiFi dip causes Netflix to drop to 1080p for a second, unnoticed. Torbox serves raw MKV files at **fixed bitrate** (~80-100 Mbps for 4K HDR). Any bandwidth dip causes buffering.

Additionally, **StremThru middleware** (`stremthru.13377001.xyz`) was in the path, adding latency and potentially routing through slower CDN endpoints.

The actual fix: **Disable StremThru**. The comet proxy toggle was a red herring - we disabled it thinking it was causing double-proxying, then re-enabled it when that didn't help. The proxy setting ended up back where it started.

The working path:
```
Torbox → Comet proxy (cluster, wired) → Android TV (WiFi, LAN only)
```

With StremThru disabled, comet talks directly to Torbox's API without the middleware hop.

## Contributing Factors

- **Misunderstanding stremio-server's role**: Assumed it proxied all video, but it only handles transcoding and subtitles
- **StremThru middleware**: Added unnecessary hop and potential CDN routing issues
- **Fixed vs adaptive bitrate**: 4K MKV files have no tolerance for bandwidth variation
- **WiFi for internet vs LAN**: WiFi can have micro-drops that don't affect adaptive streaming but kill fixed-bitrate playback

## What I Was Wrong About

- **"Stremio-server proxies video streams"** - It doesn't by default; it's primarily for transcoding and subtitle handling
- **"WiFi is fine because Netflix works"** - Netflix adapts to bandwidth; raw MKVs don't. Apples to oranges.
- **"Disabling comet proxy removes a hop"** - It did, but it also moved the internet-side bandwidth requirement to WiFi instead of the cluster's wired connection
- **"StremThru is helping"** - It was just adding latency without clear benefit since Torbox was configured directly

## What Helped

- **User's debugging insight**: "Netflix/Prime works fine" revealed the adaptive vs fixed bitrate distinction
- **User's Torbox test**: Confirming dashboard downloads were fast ruled out Torbox as the issue
- **Clear component separation**: Each service (comet, stremio-server, StremThru) has distinct responsibilities, making it possible to reason about the path

## What Could Have Been Worse

- **Blamed the wrong component**: Could have spent hours optimizing stremio-server resources when it wasn't even in the video path
- **Kept adding resources**: Without understanding the architecture, might have just kept scaling up pods uselessly

## Is This a Pattern?

- [x] One-off: Correct and move on
- [ ] Pattern: Revisit the approach

This was a configuration/understanding issue, not a systemic problem. Now that the video path is understood and documented, future debugging will be faster.

## Action Items

- [x] Disable StremThru middleware (completed: 9fcd23c) - **the actual fix**
- [x] Increase comet resources for 4K streaming (completed: 9fcd23c) - precautionary, but pod was only using 2m/336Mi of 500m/1Gi limits, so not the cause
- [ ] Document the Stremio video path in repo README or docs
- [ ] Consider ethernet adapter for Android TV if issues recur

## Lessons

- **Understand the data path**: Before optimizing, trace exactly where bytes flow. Assumptions about "what proxies what" were wrong.
- **Adaptive vs fixed bitrate**: Streaming services (Netflix, YouTube) adapt to bandwidth. Raw video files (MKV, MP4) don't. This explains why "WiFi is fast enough" can be true for one and false for the other.
- **Wired > WiFi for sustained throughput**: WiFi can have micro-drops that don't show up in speed tests but cause buffering for fixed-bitrate content.
- **Middleware isn't always helping**: StremThru was adding complexity without clear benefit. When in doubt, simplify the path.
- **Next time I see streaming buffering**: First question is "what's the actual path?" - trace it from source to player before changing anything.
