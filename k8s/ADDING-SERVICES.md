# Adding Services to k3s

## Directory Structure

Create a new directory for your app:

```
k8s/apps/your-app/
├── kustomization.yaml   # Lists all files to apply
├── namespace.yaml       # Isolated space for your app
├── deployment.yaml      # The container(s) to run
├── service.yaml         # How to expose it
├── configmap.yaml       # Configuration (optional)
└── pvc.yaml             # Persistent storage (optional)
```

## Core Resources

### 1. Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: your-app
```

### 2. Deployment

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

### 3. Service

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

### 4. Persistent Storage (Optional)

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
  storageClassName: local-path
```

**Note:** `local-path` is node-local. If pod moves to another node, it loses access to the data. For shared storage, use NFS from faramir.

### 5. ConfigMap (Optional)

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

### 6. Kustomization

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

## Register with FluxCD

Add your app to `k8s/apps/kustomization.yaml`:

```yaml
resources:
  - adguard
  - your-app    # Add this line
```

## Workflow

1. Create files in `k8s/apps/your-app/`
2. `git add k8s/apps/your-app/` (important - FluxCD needs tracked files)
3. Commit and push
4. FluxCD auto-applies, OR manually apply:
   ```bash
   nix-shell -p kustomize --run "kustomize build k8s/apps/your-app/" | \
     ssh root@boromir.lan "kubectl apply -f -"
   ```

## Quick Reference

| Want to... | Use |
|------------|-----|
| Run a container | Deployment |
| Expose internally | Service (ClusterIP) |
| Expose externally | Service (LoadBalancer) + MetalLB |
| Store config | ConfigMap |
| Store secrets | Secret (or SOPS) |
| Persist data (single node) | PVC with local-path |
| Persist data (shared) | NFS from faramir |
| Run one-time task | Job |
| Run on schedule | CronJob |

## Storage Recommendations

| App Type | Storage |
|----------|---------|
| Stateless / config-driven | ConfigMap |
| Media (Jellyfin, Plex) | NFS |
| Databases | local-path or Longhorn |
| General stateful apps | NFS or local-path |

## Traefik IngressRoute (Recommended for HTTP Services)

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
spec:
  entryPoints:
    - web
    - websecure  # Important: Traefik redirects HTTP→HTTPS
  routes:
    - match: Host(`your-app.lan`)
      kind: Rule
      services:
        - name: your-app
          port: 8080
```

**Important:** Always include both `web` and `websecure` entrypoints. Traefik redirects HTTP to HTTPS, so if you only have `web`, HTTPS requests will 404.

**DNS:** Add a rewrite in AdGuard (`k8s/apps/adguard/configmap.yaml`):
```yaml
- domain: your-app.lan
  answer: 192.168.1.52  # Traefik LoadBalancer IP
```

## Homepage Auto-Discovery

Homepage automatically discovers services from Traefik IngressRoutes. Add these annotations to your IngressRoute:

```yaml
metadata:
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "Your App"
    gethomepage.dev/group: "Infrastructure"
    gethomepage.dev/icon: "your-app.png"
    gethomepage.dev/description: "Short description"
    gethomepage.dev/href: "https://your-app.lan"
```

| Annotation | Required | Description |
|------------|----------|-------------|
| `enabled` | Yes | Set to "true" to discover |
| `name` | Yes | Display name on dashboard |
| `group` | Yes | Section grouping (e.g., "Infrastructure", "Media", "Smart Home") |
| `icon` | No | Icon from [dashboard-icons](https://github.com/walkxcode/dashboard-icons) |
| `description` | No | Subtitle text |
| `href` | **Yes** | URL when clicked (required for IngressRoutes) |

## Common Gotchas

1. **Labels must match** - `selector.matchLabels` must match `template.metadata.labels`
2. **Namespace everywhere** - Include `namespace: your-app` in every resource
3. **Git add new files** - Nix flakes and FluxCD only see tracked files
4. **MetalLB IPs** - Pick unused IPs from pool (192.168.1.50-59)
5. **Image pull fails** - Usually DNS issues; check CoreDNS is working

## Useful Commands

```bash
# Check pod status
ssh root@boromir.lan "kubectl get pods -n your-app"

# Check logs
ssh root@boromir.lan "kubectl logs -n your-app -l app=your-app"

# Describe pod (see events/errors)
ssh root@boromir.lan "kubectl describe pod -n your-app -l app=your-app"

# Restart deployment
ssh root@boromir.lan "kubectl rollout restart deployment your-app -n your-app"

# Delete and recreate
ssh root@boromir.lan "kubectl delete -k k8s/apps/your-app/"
nix-shell -p kustomize --run "kustomize build k8s/apps/your-app/" | \
  ssh root@boromir.lan "kubectl apply -f -"
```
