# Kubernetes Cluster (k3s)

## k3s

- **IPVS + NixOS firewall**: pod → ClusterIP traffic arrives on the INPUT chain via `cni0` and gets dropped by `nixos-fw` before IPVS can intercept. Fix is the `iptables -I nixos-fw 1 -i cni0 -s 10.42.0.0/16 -d 10.43.0.0/16 -j nixos-fw-accept` rule in `modules/nixos/server/k3s.nix`'s `networking.firewall.extraCommands`.
- **Flannel + keepalived VIP corruption**: flannel picks up keepalived VIPs (52–56) as its public-ip, corrupting host-gw routes cluster-wide. `--flannel-iface` alone is NOT sufficient; must also `--flannel-external-ip` + `--node-external-ip=<nodeIp>` so the CCM sets the `flannel.alpha.coreos.com/public-ip-overwrite` annotation. Setting that annotation manually is ignored — it has to go through the CCM.
- **Dual-stack IPv6 for pods is BLOCKED**: the single-stack → dual-stack migration crashes flannel (k3s-io/k3s#10726, nil pointer in `WriteSubnetFile`). Migration would require deleting ALL node objects and restarting simultaneously. Don't attempt.
- **Post-flannel-change ritual**: restart ALL Longhorn instance-managers + CSI sidecars (attacher/provisioner/resizer/snapshotter). Stale pods inherit old IPs and break DNS/connectivity silently.
- **Flux `GitRepository.spec.depth` does NOT exist** in source-controller v1 API (v1.7.4). Only the archive `ignore` filter is available.

## Bifrost (LLM Gateway)

- **Virtual keys MUST be declared in the HelmRelease** `governance.virtualKeys` with `value: "env.VAR_NAME"`. Dashboard-only keys are lost on PVC recreation.
- **Anthropic endpoint translation is broken for z.ai / DeepSeek** (v1.3.0+): Bifrost's `/anthropic/v1/messages` unconditionally translates to OpenAI **Responses API** (`/v1/responses`), not Chat Completions. Only `cliproxy` works as a flexible passthrough. Upstream fix in PR #2599.
- **zai provider needs explicit `models:` whitelist** per key (coding-PaaS tier quirk). Other providers forward any model string unchanged.
- **open-webui's `zai/glm-4.7` facade actually routes to DeepSeek** via an initContainer in `k8s/apps/open-webui/deployment.yaml` (`base_model_id = "deepseek/deepseek-chat"`). The UI label does not match the backend — don't trust the label when debugging.

## HolmesGPT

- At `https://holmes.lan` (self-signed — use `curl -sk`). API field is `ask`, NOT `question`: `POST /api/chat {"ask": "...", "model": "bifrost-kimi"}`. Helm service: `holmesgpt-holmes:80` → container `5050`.
