# helm-charts

Helm charts I maintain for my home cluster.

## Publishing

- Chart API version: `v2`
- Chart path: `charts/<chart>`
- Release/index automation: GitHub Actions (`.github/workflows/release.yml`)
- Chart repository branch: `gh-pages`

## Repo Layout

- `charts/<chart>/` contains a chart definition
- `scripts/` contains local/CI helpers

## Local Lint

```bash
./scripts/lint.sh
```

## Using The Chart Repository

After the release workflow has published `index.yaml` to `gh-pages`:

```bash
helm repo add mgarratt-home https://mgarratt.github.io/helm-charts
helm repo update
helm search repo mgarratt-home
```

One-time repository setup: enable GitHub Pages with source branch `gh-pages` and folder `/ (root)`.

## Adding A Chart

1. Copy `charts/_template/` to `charts/<chart>/`.
2. Edit `charts/<chart>/Chart.yaml`.
3. Edit `charts/<chart>/values.yaml` and `charts/<chart>/templates/*`.
