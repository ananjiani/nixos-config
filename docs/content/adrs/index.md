# Architecture Decision Records

Documenting the rationale behind homelab infrastructure decisions.

ADRs capture *why* a choice was made, what alternatives were considered, and what tradeoffs were accepted. When context changes, they provide the information needed to re-evaluate.

| # | Date | Title | Status |
|---|------|-------|--------|
| [ADR-001](adr-001-openbao-secrets-management.md) | 2026-01-25 | OpenBao secrets management | Accepted |
| [ADR-002](adr-002-headscale-on-erebor.md) | 2026-04-20 | Move Headscale from k3s to erebor VPS | Accepted |
| [ADR-003](adr-003-2026-05-21-ups-graceful-shutdown-architecture.md) | 2026-05-21 | UPS graceful shutdown architecture | Accepted |
| [ADR-004](adr-004-2026-07-13-desktop-mullvad-tailscale-coexistence.md) | 2026-07-13 | Stop excluding Tailscale from Mullvad on ammars-pc | Proposed |
| [ADR-005](adr-005-2026-07-20-doom-emacs-unstraightened.md) | 2026-07-20 | Manage Doom Emacs declaratively with nix-doom-emacs-unstraightened | Accepted |
| [ADR-006](adr-006-2026-07-20-kubernetes-https-edge-for-pi-web.md) | 2026-07-20 | Kubernetes HTTPS edge for pi-web on the desktop | Accepted |
| [ADR-007](adr-007-2026-07-27-portable-dev-home-profile.md) | 2026-07-27 | Portable Home Manager dev profile + host homelab overlay | Accepted |
| [ADR-008](adr-008-2026-08-03-denethor-searxng-lan-pinhole.md) | 2026-08-03 | Denethor web search via LAN pinhole to SearXNG | Accepted |
| [ADR-009](adr-009-2026-08-19-comin-pull-deployments.md) | 2026-08-19 | Comin pull deployments with Buildbot CI and activity-aware desktop deploy | Accepted |
| [ADR-010](adr-010-2026-08-19-erebor-primary-ntfy.md) | 2026-08-19 | Make Erebor the primary ntfy notification endpoint | Accepted |
| [ADR-011](adr-011-2026-08-20-project-supervisor-agents.md) | 2026-08-20 | Optional Project Supervisor agents in Herdr with Telegram | Superseded by [ADR-012](adr-012-2026-08-24-multi-host-project-supervisors.md) |
| [ADR-012](adr-012-2026-08-24-multi-host-project-supervisors.md) | 2026-08-24 | One Telegram bot per Project Supervisor host | Accepted |
| [ADR-013](adr-013-2026-08-27-isolate-buildbot-nix-store.md) | 2026-08-27 | Isolate Buildbot onto a dedicated Nix store daemon | Accepted |
