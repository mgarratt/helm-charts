# Charts

Each subdirectory in `charts/` is one Helm chart.

- Create a new chart by copying `charts/_template/` to `charts/<chart>/` and editing.
- CI and local lint should run from `scripts/lint.sh`.

## Available

- `proton-bridge`: Deploys Proton Mail Bridge for in-cluster SMTP/IMAP access.
