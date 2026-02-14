# proton-bridge

Deploys `ghcr.io/mgarratt/docker-images/proton-bridge` as a single-replica Helm release for in-cluster SMTP/IMAP access.

## Login Workflow

Proton Bridge can only run a single process against its state directory. To log in interactively, scale the main Deployment to `0`, run a temporary CLI pod with `BRIDGE_MODE=cli`, then scale back up.

This workflow expects `persistence.enabled=true` (default) so `/home/bridge` is backed by the chart PVC and login data persists.

```bash
NAMESPACE=default
RELEASE=proton-bridge
DEPLOYMENT="$(kubectl -n "$NAMESPACE" get deploy \
  -l app.kubernetes.io/instance="$RELEASE",app.kubernetes.io/name=proton-bridge \
  -o jsonpath='{.items[0].metadata.name}')"
IMAGE="$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT" -o jsonpath='{.spec.template.spec.containers[0].image}')"
SECRET_NAME="$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT" -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].secretRef.name}')"
PVC_NAME="$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT" -o jsonpath='{.spec.template.spec.volumes[?(@.name=="bridge-data")].persistentVolumeClaim.claimName}')"

# stop the main bridge process
kubectl -n "$NAMESPACE" scale deploy/"$DEPLOYMENT" --replicas=0
kubectl -n "$NAMESPACE" rollout status deploy/"$DEPLOYMENT"

# start a temporary interactive bridge process in CLI mode
kubectl -n "$NAMESPACE" run "${RELEASE}-login" \
  --rm -it --restart=Never \
  --image "$IMAGE" \
  --overrides "$(cat <<JSON
{
  \"apiVersion\": \"v1\",
  \"spec\": {
    \"containers\": [
      {
        \"name\": \"proton-bridge\",
        \"image\": \"$IMAGE\",
        \"env\": [{\"name\":\"BRIDGE_MODE\",\"value\":\"cli\"}],
        \"envFrom\": [{\"secretRef\":{\"name\":\"$SECRET_NAME\"}}],
        \"stdin\": true,
        \"tty\": true,
        \"volumeMounts\": [{\"name\":\"bridge-data\",\"mountPath\":\"/home/bridge\"}]
      }
    ],
    \"volumes\": [
      {
        \"name\": \"bridge-data\",
        \"persistentVolumeClaim\": {
          \"claimName\": \"$PVC_NAME\"
        }
      }
    ]
  }
}
JSON
)"

# after login and exit from the CLI pod, start normal service mode again
kubectl -n "$NAMESPACE" scale deploy/"$DEPLOYMENT" --replicas=1
kubectl -n "$NAMESPACE" rollout status deploy/"$DEPLOYMENT"
```

## Defaults

- Service type: `ClusterIP`
- Service ports: SMTP `25`, IMAP `143` (mapped to container ports `1025`/`1143` by default)
- Image tag: `latest`
- PVC: enabled, `ReadWriteOnce`, `2Gi`

## Required Runtime Configuration

The image requires the following environment variables:

- `PROTON_BRIDGE_SMTP_PORT`
- `PROTON_BRIDGE_IMAP_PORT`
- `PROTON_BRIDGE_HOST`
- `CONTAINER_SMTP_PORT`
- `CONTAINER_IMAP_PORT`

By default, the chart creates a Secret with values from `values.yaml`. Set `existingSecret` to reuse your own Secret.

## Install

```bash
helm upgrade --install proton-bridge ./charts/proton-bridge
```

## Configure

Common overrides:

- `image.tag`
- `service.type`
- `persistence.existingClaim`
- `bridge.host`, `bridge.smtpPort`, `bridge.imapPort`
- `container.smtpPort`, `container.imapPort`
- `container.enablePrivilegedPortBinding`
- `podSecurityContext.fsGroup`
- `containerSecurityContext`
- `volumePermissions.enabled`
- `existingSecret`

To bind directly on container ports `25` and `143`, enable privileged port binding:

```yaml
container:
  smtpPort: 25
  imapPort: 143
  enablePrivilegedPortBinding: true
```

## Troubleshooting Startup Permission Errors

If the container cannot write under `/home/bridge` at startup, set a pod `fsGroup` so Kubernetes adjusts volume group ownership:

```yaml
podSecurityContext:
  fsGroup: 1000
```

If your storage backend still needs explicit ownership fixes, enable the permissions init container:

```yaml
volumePermissions:
  enabled: true
  chown: "1000:1000"
```
