---
date: 2026-04-01
title: Use OpenBao on external VPS for secrets management
status: proposed
supersedes:
superseded_by:
systems: [secrets, nixos, kubernetes, terraform, ci-cd]
tags: [infrastructure, secrets, security, openbao, vault]
---

## Context and Problem Statement

The homelab uses SOPS-nix with age encryption for all secrets (37 NixOS secrets, 18 Kubernetes secret manifests, 4 Terraform secrets). While SOPS works well for at-rest encryption, it creates friction when AI coding agents (Claude Code) work on infrastructure: the agent either can't access secret references it needs to write valid configs, or risks exposing plaintext values in its context window. SOPS also lacks a UI, audit trail, secret versioning, and dynamic credential capabilities — limitations that compound as the infrastructure grows.

## Decision Drivers

- AI coding agents need to work with secret references without seeing plaintext values
- Must be fully self-hostable (no cloud vendor dependency for the secrets backend itself)
- Career value: Vault/OpenBao skills are highly in-demand for DevOps/SRE/Platform roles
- NixOS ecosystem support (modules, packages, vault-agent integration)
- Must solve the bootstrap problem: secrets must be available before homelab services start

## Considered Options

1. OpenBao on external VPS (Hetzner)
2. Infisical on k3s cluster
3. HashiCorp Vault on external VPS
4. Keep SOPS-nix (status quo)

## Decision Outcome

Chosen option: "OpenBao on external VPS", because it provides the MCP integration needed for AI agents, has first-class NixOS support via `services.openbao` and `services.vault-agent`, builds career-transferable Vault skills (API-compatible), and running on an external VPS eliminates the bootstrap chicken-and-egg problem that in-cluster solutions have.

### Consequences

- Good: AI agents can safely interact with secrets via MCP (list + metadata only, no plaintext reads)
- Good: Full audit trail of every secret access with OpenBao's audit logging
- Good: Web UI for human-friendly secret management replaces `sops secrets/secrets.yaml` workflow
- Good: Career-relevant Vault skills transfer directly to enterprise environments
- Good: External VPS means secrets are always available, independent of homelab state
- Bad: New monthly cost (~EUR 5/month for Hetzner CX22 + ~$1/month for AWS KMS auto-unseal)
- Bad: New external dependency — if VPS is unreachable, new deployments and service restarts that need fresh secrets will fail
- Bad: Migration effort across NixOS hosts, Kubernetes, and Terraform is significant (estimated 7-10 days)
- Neutral: One SOPS secret remains for bootstrapping the vault-agent AppRole credentials on each host

### Confirmation

OpenBao is working when: (1) `bao status` shows unsealed after an unattended VPS reboot, (2) at least one NixOS host has been fully migrated from sops-nix to vault-agent with services starting correctly, (3) Claude Code can list secret paths and metadata via MCP without seeing plaintext values.

## Pros and Cons of the Options

### OpenBao on external VPS

- Good: Fully open source (MPL 2.0), community-governed under Linux Foundation
- Good: API-compatible with HashiCorp Vault — all Vault tooling, docs, and MCP servers work
- Good: `services.openbao` NixOS module in nixpkgs 25.11+, actively maintained
- Good: `services.vault-agent` in nixpkgs for client-side secret fetching
- Good: External VPS solves bootstrap — available before homelab k3s/NixOS services start
- Good: Kubernetes auth method works with k3s for pod-level secret injection
- Good: Raft integrated storage needs no external database (self-contained on single VPS)
- Neutral: AWS KMS adds a small cloud dependency for auto-unseal only (not for secret storage)
- Bad: Single VPS is a single point of failure for secret delivery
- Bad: Operational overhead of running another service (backups, updates, monitoring)

### Infisical on k3s cluster

- Good: Modern UI/UX, purpose-built for developer workflows
- Good: Official MCP server with full CRUD capabilities
- Good: Native Kubernetes Operator with CRD-based secret syncing
- Good: MIT licensed, fully self-hostable
- Neutral: Requires PostgreSQL + Redis (heavier than OpenBao's embedded Raft)
- Bad: Running on k3s creates bootstrap chicken-and-egg — k3s needs secrets to start, but Infisical runs on k3s
- Bad: No NixOS module for the server (Helm chart only)
- Bad: No `vault-agent` equivalent for NixOS system-level secret delivery
- Bad: Low job market demand — skills don't transfer to enterprise roles

### HashiCorp Vault on external VPS

- Good: Industry standard with the largest ecosystem and community
- Good: Official MCP server, guaranteed compatible
- Good: `services.vault` NixOS module with 14+ configuration options
- Good: Maximum career value — listed on most DevOps/SRE job postings
- Neutral: Feature-identical to OpenBao for homelab use cases
- Bad: Business Source License (BSL) — not truly open source since 2023
- Bad: License restricts competing commercial use (not a homelab concern, but principle matters)
- Bad: Same operational overhead as OpenBao with no additional benefit for this use case

### Keep SOPS-nix (status quo)

- Good: Zero additional cost or infrastructure
- Good: Simple mental model — encrypted files in git, decrypted at activation time
- Good: Already working and well-understood across the entire stack
- Good: No migration effort
- Bad: AI agents cannot safely interact with secrets (the core problem)
- Bad: No audit trail of secret access
- Bad: No web UI — editing requires `sops` CLI and age key
- Bad: No secret versioning or rotation capabilities
- Bad: All-or-nothing access — age key decrypts every secret simultaneously
