---
date: 2026-09-06
title: OpenBao Raft snapshots silently 403'd for four months after the backup token expired
severity: major
duration: 124 days (2026-05-06 – 2026-09-06)
systems: [erebor, openbao, restic, backup]
tags: [openbao, backup, tokens, monitoring, alert-fatigue]
commit: https://codeberg.org/ananjiani/infra/pulls/313
---

## Summary

Erebor's nightly OpenBao Raft snapshot (`openbao-backup.service`) failed with
`403 permission denied` every midnight from 2026-05-06 through 2026-09-06.
The last good local snap is `openbao-20260505-000004.snap`. OpenBao itself
stayed unsealed and serving. Restic still ran at 01:00 and uploaded the
stale April/May files to B2, so the offsite job looked healthy. A live
OpenBao loss in that window would have restored to a four-month-old
snapshot. Discovered while checking failed units after the NixCI gate
rollout; not from an alert.

## Timeline

All times CDT (UTC-5).

- **~Apr 4** — Periodic backup token created in `/var/lib/openbao/backup-env`
  (`BAO_TOKEN=…`, 768h period). Daily snaps start accumulating.
- **May 5 00:00** — Last successful snapshot:
  `/var/backup/openbao/openbao-20260505-000004.snap`.
- **May 6 00:00** — Token period elapsed. `bao operator raft snapshot save`
  hits `GET http://127.0.0.1:8200/v1/sys/storage/raft/snapshot` → `403
  permission denied`. Unit exits 2. Same failure every midnight afterward
  (journal from Aug 31–Sep 6 is the surviving window; the snap directory
  stops at May 5).
- **May 6 01:00 onward** — `restic-backups-openbao-offsite.service` succeeds
  against `/var/backup/openbao`, shipping the last good files. Offsite
  snapshot size stays ~3.991 MiB of old snaps.
- **Sep 6 ~04:11** — Fleet check after PR #296 merge lists
  `openbao-backup.service` failed on erebor. Left untouched (unrelated to
  that rollout).
- **Sep 6 ~11:40** — Investigation starts. OpenBao unsealed (v2.6.2). Token
  `lookup-self` is 403. Zero accessors with the `backup` policy.
- **Sep 6 12:00** — Throwaway token with terraform `backup` policy (`read` on
  `sys/storage/raft/snapshot`) takes a snapshot. Policy is sufficient; the
  on-disk token is dead.
- **Sep 6 12:01** — New 768h periodic token
  (`display_name=erebor-openbao-backup`, policies `backup`+`default`) written
  to `backup-env` (root:root 0600). `openbao-backup.service` succeeds:
  `openbao-20260906-120123.snap` (200747 bytes). Failed unit clears.
- **Sep 6 12:02** — Restic offsite run succeeds; newest restic snapshot is
  196 KiB at 12:02.
- **Sep 6 12:03** — PR #313 opened: renew the token on every backup run.

## What Happened

`openbao-backup.service` is a daily oneshot. It sources
`-/var/lib/openbao/backup-env` and runs `bao operator raft snapshot save`
against `http://127.0.0.1:8200`. The token is imperative — created once,
never declared in terraform, never renewed. A 768h periodic token dies
unless something calls `bao token renew` inside that period.

Nothing did. After ~32 daily successes (Apr 4–May 5) the token expired.
Every later run 403'd. Retention (`find … -mtime +30 -delete`) only runs
after a successful snapshot, so the April/May files sat on disk and restic
kept uploading them.

The terraform `backup` policy was a red herring during the first read of
the logs. HashiCorp Vault docs often require `sudo` on raft snapshots;
OpenBao 2.6.2 does not. A five-minute token with only `read` on
`sys/storage/raft/snapshot` saved a snap. `lookup-self` 403 plus zero
`backup`-policy accessors was the actual signal.

`HostSystemdUnitFailed` already matches erebor's node exporter
(`job=nixos-node-exporter`, `for: 5m`, severity warning). The oneshot
stays `failed` until the next run, so the alert should have been pending
for four months. It did not cause a response. Same shape as the 2026-09-04
Attic outage: coverage existed, signal quality did not.

## Contributing Factors

- Periodic token with no renew in the backup script. A 768h period is a
  silent fuse, not a safety net.
- Token issuance is a one-shot operator action (`backup-env` after initial
  setup). Terraform manages the policy, not the token. No AppRole, no
  reminder, no expiry metric.
- Restic success is the wrong health signal. It backs up a directory, not
  "OpenBao produced a snap today."
- Snapshot retention only runs on success, so stale files look like a
  healthy archive.
- `HostSystemdUnitFailed` is a warning on the shared monitoring topic.
  A failed oneshot blends into routine noise.

## What I Was Wrong About

- "Restic succeeded, so OpenBao backups are current." Restic succeeded at
  copying old files. Freshness was never checked.
- "A 403 on `/sys/storage/raft/snapshot` means the policy needs `sudo`."
  The live policy was enough. The token was gone.
- "A failed systemd unit on erebor would have been noticed." The generic
  failed-unit alert is a warning. Four months of 403s did not page anyone.
  The unit was found by an SSH `systemctl --failed` during unrelated work.

## What Helped

- Local snap filenames are datestamped. `ls -lt /var/backup/openbao`
  showed the last success immediately (May 5), independent of journal
  retention.
- `bao token lookup` against the sourced env failed closed on
  `lookup-self` (403), which is a stronger signal than the snapshot 403
  alone.
- The `backup` policy could be proven with a throwaway token before
  touching the host file.
- Restic still had the May 5 snaps offsite. Disaster recovery would have
  been stale, not empty.

## What Could Have Been Worse

- An OpenBao disk loss or bad Raft state between May 6 and Sep 6 would
  have restored secrets as of May 5 — four months of KV writes, AppRole
  secret-ids, and policy changes gone.
- The May 5 snaps are tiny (~75 KiB vs 200 KiB today). That gap is real
  data, not metadata noise.
- If `find -mtime +30 -delete` had run (it doesn't on failure), even the
  stale local copies would be gone. Restic's 3.991 MiB blobs were the
  only remaining history.

## Is This a Pattern?

- [x] Pattern: Revisit the approach

Two patterns, both seen before:

1. **An auxiliary job succeeding on stale inputs hides the upstream
   failure.** Restic green ≠ snapshot fresh. Same class as "Flux
   reconciled" while ExternalSecrets were frozen
   (`2026-05-01-2100-cordoned-nodes-12-day-eso-outage.md`).
2. **Warning-level unit-failed alerts do not produce a response.**
   `2026-09-04-1110-atticd-anonymous-db-user.md` already named alert
   fatigue. This incident is the same ntfy topic, four months instead of
   one hour.

Imperative periodic tokens without renew are a third, smaller pattern:
they work until the calendar catches them.

## Action Items

- [x] Mint a new 768h periodic token into `/var/lib/openbao/backup-env`
      and take a snapshot (2026-09-06 12:01 CDT)
- [x] Run restic offsite so B2 holds the new snap (12:02 CDT)
- [x] Renew the token at the start of `openbao-backup.service` (this PR)
- [ ] Alert on OpenBao snapshot age (newest
      `/var/backup/openbao/*.snap` mtime > 36h), not only on unit failed
- [ ] Confirm `HostSystemdUnitFailed` actually fired for
      `openbao-backup.service` on erebor; if it did, treat that as more
      evidence for the 2026-09-04 ntfy signal-quality action items

Skipped: moving issuance to an AppRole. Add if we want the token itself
to be declarative; renew-on-run already removes the 32-day fuse.

## Lessons

- A periodic Vault/OpenBao token that is never renewed will die on a
  quiet calendar boundary, not during a deploy.
- `restic backup /var/backup/openbao` succeeding only proves the
  directory was readable. Check the newest snap's mtime (or size change)
  before trusting offsite.
- `403` on a snapshot endpoint is "this token cannot do this," not
  "this policy document is wrong." Prove the token with `lookup-self`
  before editing terraform.
- `HostSystemdUnitFailed` at warning severity is not an OpenBao backup
  monitor.
