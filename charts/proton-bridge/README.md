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
- Service ports: SMTP `25`, IMAP `143` (mapped to container ports `1026`/`1144` by default)
- Image tag: `latest`
- Bridge mode: `grpc` (serves mail plus the gRPC API the metrics exporter scrapes)
- Metrics: exporter on container port `9154`; `PodMonitor` off by default
- Update strategy: `Recreate` (single `ReadWriteOnce` volume)
- PVC: enabled, `ReadWriteOnce`, `2Gi`

## Metrics

The image runs a Prometheus exporter (container port `container.metricsPort`,
default `9154`) when `bridge.mode=grpc` (the default). Enable scraping with the
Prometheus Operator:

```yaml
podMonitor:
  enabled: true
```

## Required Runtime Configuration

The image requires the following environment variables:

- `PROTON_BRIDGE_SMTP_PORT`
- `PROTON_BRIDGE_IMAP_PORT`
- `PROTON_BRIDGE_HOST`
- `CONTAINER_SMTP_PORT`
- `CONTAINER_IMAP_PORT`
- `CONTAINER_METRICS_PORT`
- `CONTAINER_SMTP_TLS_CERT_FILE`
- `CONTAINER_SMTP_TLS_KEY_FILE`

The chart sets the first six from `values.yaml`. The last two come from the
image's own defaults unless `certificate.secretName` is set, in which case the
chart sets them to match the mounted certificate.

By default, the chart creates a Secret with values from `values.yaml`. Set `existingSecret` to reuse your own Secret.

## Certificate (STARTTLS)

The image's `smtp-relay` service (mgarratt/docker-images#8) terminates STARTTLS
at the pod boundary and requires a certificate/key on disk. To mount one:

```yaml
certificate:
  secretName: proton-bridge-tls
```

`secretName` must name a Kubernetes TLS-type Secret (keys `tls.crt`/`tls.key`,
e.g. one managed by cert-manager). Mounted at `certificate.mountPath` (default
`/etc/proton-bridge/tls`), it lines up with the image's own defaults for
`CONTAINER_SMTP_TLS_CERT_FILE`/`CONTAINER_SMTP_TLS_KEY_FILE`, so no other
overrides are needed. Leave `secretName` empty (the default) and the chart
renders exactly as before.

That is safe only on an image built before `mgarratt/docker-images@2a98d13`. From
that revision onward the image requires a certificate on disk and fails fast
without one, so any release running such an image **must** set
`certificate.secretName`. Neither the `latest` tag nor a version tag such as
`3.25.0` tells you which image you have — both move forward as new images
publish — so if you need to stay on an image before `2a98d13`, pin `image.digest`
rather than a tag.

## Install

```bash
helm upgrade --install proton-bridge ./charts/proton-bridge
```

## Configure

Common overrides:

- `image.tag`, `image.digest` (pin by digest: referenced as `repo:tag@digest`)
- `bridge.mode` (`grpc` default, `noninteractive`, or `cli`)
- `strategy` (defaults to `Recreate`)
- `podMonitor.enabled`, `podMonitor.interval`, `podMonitor.labels`
- `service.type`
- `persistence.existingClaim`
- `bridge.host`, `bridge.smtpPort`, `bridge.imapPort`
- `container.smtpPort`, `container.imapPort`, `container.metricsPort`
- `container.enablePrivilegedPortBinding`
- `containerSecurityContext`
- `volumePermissions.enabled`
- `existingSecret`
- `certificate.secretName`, `certificate.mountPath`, `certificate.certFile`, `certificate.keyFile`

If `bridge.host` is local (`127.0.0.1`, `localhost`, `::1`) and `container.*Port` matches `bridge.*Port`, the chart automatically shifts container ports by `+1` to avoid bridge/socat bind conflicts during installs and upgrades.

To bind directly on container ports `25` and `143`, enable privileged port binding:

```yaml
container:
  smtpPort: 25
  imapPort: 143
  enablePrivilegedPortBinding: true
```

## Troubleshooting Startup Permission Errors

By default, the chart runs the container as uid/gid `1000:1000` and sets pod `fsGroup: 1000`, matching the current image defaults.

If you need different ownership semantics for your storage class, override the security contexts:

```yaml
podSecurityContext:
  fsGroup: 1001

containerSecurityContext:
  runAsUser: 1001
  runAsGroup: 1001
```

If your storage backend still needs explicit ownership fixes, enable the permissions init container:

```yaml
volumePermissions:
  enabled: true
  chown: "1000:1000"
```
