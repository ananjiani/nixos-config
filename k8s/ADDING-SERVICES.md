# Adding Services to k3s

## Directory Structure

Create a new directory for your app:

```
k8s/apps/your-app/
├── kustomization.yaml   # Lists all files to apply
├── namespace.yaml       # Isolated space for your app
├── helmrelease.yaml     # Helm chart deployment (recommended)
├── ingressroute.yaml    # Traefik routing (for HTTP services)
└── pvc.yaml             # Persistent storage (if not managed by chart)
```

## Using Helm Charts (Recommended)

Prefer Helm charts over raw manifests when available. They handle deployments, services, configmaps, and often persistence automatically.

### 1. Find a Helm Chart

Search for charts at:
- [ArtifactHub](https://artifacthub.io/) - Main Helm chart registry
- GitHub repos of the project you want to deploy

### 2. Add HelmRepository (if new source)

Add the chart repository to `k8s/infrastructure/sources/helm-repos.yaml`:

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: chart-repo-name
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.example.com
```

### 3. Create Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: your-app
```

### 4. Create HelmRelease

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: your-app
  namespace: your-app
spec:
  interval: 1h
  chart:
    spec:
      chart: chart-name
      version: ">=1.0.0"
      sourceRef:
        kind: HelmRepository
        name: chart-repo-name
        namespace: flux-system
      interval: 1h
  values:
    # Chart-specific values go here
    # Check the chart's values.yaml for available options
    image:
      tag: latest
    persistence:
      enabled: true
      storageClass: longhorn
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
```

### 5. Kustomization

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrelease.yaml
  - ingressroute.yaml  # if HTTP service
  # - pvc.yaml         # if chart doesn't manage storage
```

### Real Examples

**ChromaDB** (simple chart):
```yaml
values:
  chromadb:
    isPersistent: true
    anonymizedTelemetry: false
    serverHttpPort: 8000
    data:
      volumeSize: 10Gi
      storageClass: longhorn
      accessModes:
        - ReadWriteOnce  # Must be array format
```

**Open WebUI** (with external services):
```yaml
values:
  ollama:
    enabled: false  # Using external Ollama
  openai:
    enabled: true
    baseUrl: "http://ollama.ollama.svc:11434/v1"
  pipelines:
    enabled: false
  persistence:
    enabled: true
    storageClass: longhorn
```

**AdGuard Home** (with MetalLB LoadBalancer):
```yaml
values:
  services:
    dns:
      type: LoadBalancer
      externalTrafficPolicy: Local
      annotations:
        metallb.universe.tf/loadBalancerIPs: "192.168.1.53"
      tcp:
        port: 53
      udp:
        port: 53
    http:
      type: LoadBalancer
      annotations:
        metallb.universe.tf/loadBalancerIPs: "192.168.1.54"
  bootstrapConfig:
    # Full AdGuard config here
```

### Helm Chart Gotchas

1. **Check service names** - Helm charts often use different service names than you'd expect. Check with `kubectl get svc -n your-app` after deployment
2. **accessModes must be arrays** - Use `accessModes: [ReadWriteOnce]` not `accessModes: ReadWriteOnce`
3. **MetalLB annotation only** - Don't use both `loadBalancerIP` field AND `metallb.universe.tf/loadBalancerIPs` annotation - use only the annotation
4. **Chart values structure** - Read the chart's `values.yaml` carefully; nested structure matters (e.g., `chromadb.data.volumeSize` not `data.volumeSize`)

## Register with FluxCD

Add your app to `k8s/apps/kustomization.yaml`:

```yaml
resources:
  - attic
  - your-app    # Add this line
```

## Workflow

1. Create files in `k8s/apps/your-app/`
2. `git add k8s/apps/your-app/` (important - FluxCD needs tracked files)
3. Commit and push
4. FluxCD auto-applies, OR manually trigger:
   ```bash
   ssh root@boromir.lan "flux reconcile kustomization apps --with-source"
   ```
5. Check status:
   ```bash
   ssh root@boromir.lan "kubectl get helmrelease -n your-app"
   ssh root@boromir.lan "kubectl get pods -n your-app"
   ```

## Traefik IngressRoute (for HTTP Services)

Use a Traefik IngressRoute to expose services via a hostname (e.g., `your-app.lan`):

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: your-app
  namespace: your-app
  annotations:
    # Homepage auto-discovery (see below)
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Your App"
    gethomepage.dev/group: "Infrastructure"
    gethomepage.dev/icon: "your-app.png"
    gethomepage.dev/description: "Short description"
    gethomepage.dev/href: "https://your-app.lan"
    gethomepage.dev/pod-selector: "app.kubernetes.io/name=your-app"
    gethomepage.dev/siteMonitor: "http://your-app.your-app.svc:80"
spec:
  entryPoints:
    - web
    - websecure  # Important: Traefik redirects HTTP→HTTPS
  routes:
    - match: Host(`your-app.lan`)
      kind: Rule
      services:
        - name: your-app  # Check actual service name from Helm chart!
          port: 80        # Check actual port from Helm chart!
```

**Important:**
- Always include both `web` and `websecure` entrypoints. Traefik redirects HTTP to HTTPS, so if you only have `web`, HTTPS requests will 404.
- Helm charts often create services with different names/ports than raw manifests would. Always verify with `kubectl get svc -n your-app`.

**DNS:** Add a rewrite in `modules/nixos/server/adguard.nix` under `filtering.rewrites`:

```nix
filtering.rewrites = [
  # ... existing rewrites ...
  {
    domain = "your-app.lan";
    answer = "192.168.1.52";  # Traefik LoadBalancer IP
  }
];
```

After updating DNS rewrites, deploy to the AdGuard servers:
```bash
deploy .#theoden && deploy .#boromir && deploy .#samwise
```

## Homepage Auto-Discovery

Homepage automatically discovers services from Traefik IngressRoutes. Add these annotations to your IngressRoute:

```yaml
metadata:
  annotations:
    # Basic discovery
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Your App"
    gethomepage.dev/group: "Infrastructure"
    gethomepage.dev/icon: "your-app.png"
    gethomepage.dev/description: "Short description"
    gethomepage.dev/href: "https://your-app.lan"
    # Status checks (use internal URLs - .lan domains don't resolve in-cluster)
    gethomepage.dev/pod-selector: "app.kubernetes.io/name=your-app"
    gethomepage.dev/siteMonitor: "http://your-app.your-app.svc:80"
```

| Annotation | Required | Description |
|------------|----------|-------------|
| `enabled` | Yes | Set to "true" to discover |
| `name` | Yes | Display name on dashboard |
| `group` | Yes | Section grouping (e.g., "Infrastructure", "Media", "AI") |
| `icon` | No | Icon from [dashboard-icons](https://github.com/walkxcode/dashboard-icons) |
| `description` | No | Subtitle text |
| `href` | **Yes** | URL when clicked (required for IngressRoutes) |
| `pod-selector` | Recommended | Pod label selector for status. Helm charts often use `app.kubernetes.io/name=...` |
| `siteMonitor` | Recommended | Internal service URL for ping time (e.g., `http://svc.ns.svc:port`) |

### Homepage Widgets

For services with Homepage widget support (Immich, etc.), add widget annotations:

```yaml
metadata:
  annotations:
    # ... basic annotations above ...
    gethomepage.dev/widget.type: "immich"
    gethomepage.dev/widget.url: "http://immich-server.immich.svc:2283"
    gethomepage.dev/widget.key: "{{HOMEPAGE_VAR_IMMICH_API_KEY}}"
    gethomepage.dev/widget.version: "2"
```

**Credentials:** Use `{{HOMEPAGE_VAR_*}}` syntax - these are replaced with environment variables from the Homepage deployment. Store secrets in `k8s/apps/homepage/secret.yaml` (SOPS-encrypted) and reference via `envFrom` in the deployment.

**Widget versions:** Some services change their API over time. For example, Immich v1.118.0+ requires `gethomepage.dev/widget.version: "2"` to use the new API endpoint.

## Quick Reference

| Want to... | Use |
|------------|-----|
| Deploy an app | HelmRelease (preferred) or Deployment |
| Expose via hostname | IngressRoute |
| Expose with dedicated IP | Service (LoadBalancer) + MetalLB |
| Store config | Chart values or ConfigMap |
| Store secrets | Secret (SOPS-encrypted) |
| Persist data (replicated) | PVC with Longhorn |
| Persist data (single node) | PVC with local-path |
| Persist data (shared) | NFS from faramir |
| Run one-time task | Job |
| Run on schedule | CronJob |

## Storage Recommendations

| App Type | Storage |
|----------|---------|
| Stateless / config-driven | ConfigMap |
| Media (Jellyfin, Plex) | NFS |
| Databases | Longhorn or local-path |
| General stateful apps | Longhorn (preferred) or NFS |

## Common Gotchas

1. **Git add new files** - Nix flakes and FluxCD only see tracked files
2. **Namespace everywhere** - Include `namespace: your-app` in every resource
3. **MetalLB IPs** - Pick unused IPs from pool (192.168.1.50-59)
4. **Helm service names** - Charts create their own service names; check with `kubectl get svc`
5. **Helm service ports** - Charts often use different ports (e.g., 80 instead of 8080)
6. **accessModes array** - PVC accessModes must be arrays: `[ReadWriteOnce]`
7. **Longhorn PVC rolling updates** - Longhorn PVCs are `ReadWriteOnce`, so rolling updates can get stuck with "Multi-Attach error". Fix: use `strategy: Recreate` in your Deployment, or manually delete the stuck pod
8. **DNS cache after rewrites** - After adding AdGuard DNS rewrites, flush local cache: `resolvectl flush-caches`
9. **Flux reverts manual changes** - Manual `kubectl apply` changes get reverted by Flux on next reconcile. Always commit to Git first, then run `flux reconcile kustomization apps --with-source`
10. **HelmRelease not Ready** - Check events: `kubectl describe helmrelease -n your-app your-app`

## Useful Commands

```bash
# Check HelmRelease status
ssh root@boromir.lan "kubectl get helmrelease -A"

# Check pod status
ssh root@boromir.lan "kubectl get pods -n your-app"

# Check logs
ssh root@boromir.lan "kubectl logs -n your-app -l app.kubernetes.io/name=your-app"

# Describe pod (see events/errors)
ssh root@boromir.lan "kubectl describe pod -n your-app -l app.kubernetes.io/name=your-app"

# Check services (important for IngressRoute!)
ssh root@boromir.lan "kubectl get svc -n your-app"

# Force Flux reconcile
ssh root@boromir.lan "flux reconcile kustomization apps --with-source"

# Check HelmRelease errors
ssh root@boromir.lan "kubectl describe helmrelease -n your-app your-app"

# Restart deployment
ssh root@boromir.lan "kubectl rollout restart deployment -n your-app"
```

---

## Alternative: Raw Manifests

Use raw manifests when no Helm chart exists or for simple single-container apps.

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-app
  namespace: your-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: your-app
  template:
    metadata:
      labels:
        app: your-app
    spec:
      containers:
        - name: your-app
          image: someimage:latest
          ports:
            - containerPort: 8080
          volumeMounts:            # Optional
            - name: data
              mountPath: /data
      volumes:                     # Optional
        - name: data
          persistentVolumeClaim:
            claimName: your-app-data
```

### Service

Three types available:

| Type | Use Case |
|------|----------|
| `ClusterIP` | Internal only (default) |
| `NodePort` | Exposed on each node's IP:port |
| `LoadBalancer` | Gets a MetalLB VIP |

**LoadBalancer example** (external access):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: your-app
  namespace: your-app
  annotations:
    metallb.universe.tf/loadBalancerIPs: "192.168.1.55"
spec:
  type: LoadBalancer
  selector:
    app: your-app
  ports:
    - port: 80
      targetPort: 8080
```

**MetalLB IP Pool:** 192.168.1.50 - 192.168.1.59

### Persistent Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: your-app-data
  namespace: your-app
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn  # or local-path for node-local
```

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: your-app-config
  namespace: your-app
data:
  config.yaml: |
    key: value
    another: setting
```

### Kustomization (Raw Manifests)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  # - pvc.yaml        # if needed
  # - configmap.yaml  # if needed
```

### Raw Manifest Gotchas

1. **Labels must match** - `selector.matchLabels` must match `template.metadata.labels`
2. **Image pull fails** - Usually DNS issues; check CoreDNS is working
