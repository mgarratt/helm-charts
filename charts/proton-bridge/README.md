# proton-bridge

Deploys `ghcr.io/mgarratt/docker-images/proton-bridge` as a single-replica Helm release for in-cluster SMTP/IMAP access.

## Defaults

- Service type: `ClusterIP`
- Service ports: SMTP `25`, IMAP `143`
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
- `existingSecret`
