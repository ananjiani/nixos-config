---
date: 2026-08-19
title: Make Erebor the primary ntfy notification endpoint
status: accepted
supersedes:
superseded_by:
systems: [ntfy, gatus, alertmanager, erebor, k3s, openbao, caddy, cloudflare]
tags: [infrastructure, monitoring, notifications, security, vps]
---

## Context and Problem Statement

The existing ntfy service runs inside k3s on Longhorn. A cluster, etcd, Longhorn, home-power, or home-WAN failure can therefore remove the notification path needed to report that same failure. Stage one of issue [#84](https://codeberg.org/ananjiani/infra/issues/84) added Gatus and a parallel ntfy service on Erebor, but the Erebor service is currently anonymous within the tailnet at `http://100.64.0.21:2586`. Android delivery consequently depends on Tailscale, and ordinary Alertmanager notifications still go only to the in-cluster ntfy.

A permanent notification architecture must preserve cluster-outage visibility, avoid duplicate long-term notification systems, remain usable from a phone without Tailscale, deny anonymous Internet access, and detect failure of Erebor's own monitoring stack through a separate failure domain.

## Decision Drivers

- Notification delivery must survive failure of k3s, etcd, Longhorn, home power, and home Internet.
- The Android client must receive notifications without depending on Tailscale or Headscale.
- Public access must fail closed: TLS, authenticated publishing and subscription, topic ACLs, and no anonymous topic access.
- Machine publishers and human subscribers require least-privilege identities.
- A single operator should not maintain permanently mirrored, unsynchronized ntfy servers without a clear benefit.
- Migration must retain a bounded rollback path and avoid abrupt DNS or client cutover.
- Erebor cannot report its own total failure through services colocated on Erebor.

## Considered Options

1. Keep the in-cluster ntfy as the sole notification service.
2. Permanently mirror every notification to independent cluster and Erebor ntfy servers.
3. Make authenticated Erebor ntfy the primary service, retain cluster ntfy only through migration, and add an independent dead-man channel.
4. Replace self-hosted ntfy with a fully hosted notification platform.

## Decision Outcome

Chosen option: **make Erebor ntfy the primary notification service**, because it removes the notifier from the home-cluster failure domain without requiring two permanently mirrored topic stores.

The permanent endpoint is `https://ntfy.dimensiondoor.xyz`. Public DNS is a DNS-only A record for Erebor, Caddy terminates TLS on port 443, and ntfy's native port is not opened publicly. LAN and public resolvers give the hostname one consistent meaning; split DNS must not direct the same hostname to two independent servers.

ntfy uses default-deny authorization with separate non-admin identities:

- `gatus`: write-only access to `monitoring`.
- `alertmanager`: write-only access to `monitoring`.
- `mobile`: read-only access to `monitoring`.
- Anonymous users: no topic access.

Secrets are stored in OpenBao and rendered at runtime. Tokens and password hashes must not enter Git, Terraform state, generated Nix store configuration, or Kubernetes ConfigMaps. The Alertmanager publisher token is deliberately duplicated under a narrow `k8s/*` path so External Secrets Operator cannot read the Erebor user hashes or other clients' tokens; both copies must rotate atomically.

Alertmanager publishes to both old and new ntfy paths during a bounded soak. The old Kubernetes service remains reachable through its cluster Service and `ntfy.lan` rollback alias until acceptance. Existing unauthenticated host publishers remain on the old service through the internal, TLS-valid `ntfy-home.dimensiondoor.xyz` migration alias until they receive dedicated least-privilege identities; that alias is not the permanent public endpoint. Erebor's native listener remains available only on the trusted tailnet during this soak, with the public firewall as its boundary; after client acceptance it moves to loopback-only behind Caddy. The old service's PVC is not deleted without separate destructive approval.

An independent hosted dead-man service must receive outbound heartbeats for Erebor and its monitoring stack and alert through its own email, app, SMS, or phone channel. It does not duplicate Gatus's application probes. The old in-cluster ntfy cannot be retired until this external failure path is operating.

### Consequences

- Good: Cluster, Longhorn, home-power, and home-WAN failures no longer remove the primary notification destination.
- Good: Android delivery no longer depends on Tailscale after public HTTPS cutover.
- Good: One permanent ntfy service avoids duplicate subscriptions, message history, ACLs, and operations.
- Good: Separate publisher and subscriber identities limit token compromise.
- Good: Direct Caddy TLS avoids adding Cloudflare proxying to the delivery path.
- Bad: Erebor becomes more critical; its failure affects OpenBao, Headscale, Gatus, and ntfy.
- Bad: Public HTTPS expands the attack surface, mitigated by default-deny ACLs, Caddy, rate limits, logging, the public firewall during migration, and an eventual proxy-only listener.
- Bad: Erebor cannot notify through itself when it is down, requiring a third-party heartbeat and independent notification channel.
- Neutral: The old ntfy cache is not migrated; the rollback server remains independent during soak.

### Confirmation

This decision is working when:

1. `ntfy.dimensiondoor.xyz` resolves to Erebor from public, LAN, and cellular resolvers.
2. Caddy serves a valid certificate and public port 2586 remains closed.
3. Anonymous publish and subscribe requests are rejected.
4. Gatus and Alertmanager can publish but cannot subscribe.
5. The Android identity can subscribe but cannot publish.
6. Android receives firing and resolved notifications over cellular with Tailscale disabled.
7. Gatus and Alertmanager delivery soak for at least seven days with no unexplained failures.
8. An independent hosted heartbeat reports withheld Erebor/monitoring-stack heartbeats through a channel other than Erebor ntfy.
9. Every legacy direct publisher has a dedicated least-privilege identity on Erebor before the internal migration alias is removed.
10. The old Kubernetes ntfy is retired only after these checks and remains recoverable during the rollback window.

## Pros and Cons of the Options

### Keep in-cluster ntfy only

- Good: No migration and no new public endpoint.
- Bad: The notifier remains inside the failure domain it reports on.
- Bad: Home WAN or power failure prevents external delivery.

### Permanently mirror both ntfy servers

- Good: Either server can receive cluster-originated alerts while its path is available.
- Bad: ntfy servers do not synchronize topics or history.
- Bad: The phone receives duplicates if subscribed to both.
- Bad: Two authentication systems and caches increase single-operator complexity.
- Bad: Mirroring still does not let Erebor report its own total failure through Erebor ntfy.

### Erebor primary plus independent dead-man monitoring

- Good: Separates normal notifications from the home cluster.
- Good: Provides one stable Android endpoint.
- Good: The independent heartbeat specifically covers the remaining Erebor blind spot.
- Bad: Requires staged DNS, authentication, client, and Alertmanager migration.
- Bad: Adds an external monitoring-provider dependency for dead-man delivery.

### Fully hosted notification platform

- Good: Removes self-hosted notifier availability concerns.
- Good: May provide integrated escalation and mobile delivery.
- Bad: Moves all notification content and availability to a vendor.
- Bad: Replaces the existing ntfy workflow and conflicts with the preference to retain a self-hosted primary service.
