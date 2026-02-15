---
name: holmes
description: Investigate Kubernetes cluster issues, server problems, and infrastructure alerts using HolmesGPT. Use when user mentions pod failures, deployment issues, service outages, high resource usage, build failures, or asks to "investigate", "troubleshoot", or "check cluster health".
---

# HolmesGPT Investigation

Query HolmesGPT to investigate infrastructure issues. HolmesGPT has direct access to Kubernetes state, Prometheus metrics, Loki logs, Buildbot CI, and can run bash commands inside the cluster.

## Instructions

### Step 1: Send the investigation query

Run this command using the Bash tool, replacing QUESTION with the user's question from $ARGUMENTS. Escape double quotes in the question for valid JSON.

```bash
curl -s --max-time 300 \
  -X POST http://holmes.lan/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"question": "QUESTION", "model": "bifrost-kimi"}'
```

### Step 2: Parse and present the response

The API returns JSON. Extract the analysis from the response and present:
- Root cause or contributing factors identified
- Evidence gathered (log snippets, metric values, pod states)
- Suggested remediation steps or follow-up actions

If the response contains tool call details, summarize what data sources HolmesGPT consulted.

## Available data sources

HolmesGPT can pull from these during investigation:
- **kubernetes/core** — pod status, events, deployments, services, configmaps, secrets metadata
- **grafana/loki** — log queries across all namespaces
- **prometheus/metrics** — metric queries, alert states, resource usage
- **buildbot/ci** — build status, step logs, worker health (theoden:8010)
- **bash** — shell commands inside the cluster
- **internet** — web searches for known issues and documentation

## Error handling

### Connection refused or timeout
HolmesGPT pod may be down. Verify with:
```bash
ssh root@boromir.lan "kubectl get pods -n holmesgpt"
```

### Empty or error response about model
The configured model is `bifrost-kimi` (Kimi via Bifrost LLM gateway). Check Bifrost is healthy:
```bash
curl -s http://bifrost.lan/health
```

### Investigation taking too long
Complex investigations chain multiple tool calls (kubectl, Loki queries, Prometheus queries). If the 300s timeout is hit, break the question into smaller parts:
- Ask about pod status separately from log analysis
- Ask about metrics separately from event correlation

## Examples

- `/holmes why is the bifrost pod crashlooping?`
- `/holmes are any pods in a restart loop?`
- `/holmes investigate high memory usage on the monitoring namespace`
- `/holmes what Buildbot builds have failed in the last 24 hours?`
- `/holmes check if any Flux HelmReleases are failing to reconcile`
- `/holmes why is Loki ingester showing OOM errors?`
