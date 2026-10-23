#!/bin/sh
# Configure once (the registration token is only needed the first time), then run (harbor#1060).
# Contract with the provisioning lane: RUNNER_URL, RUNNER_NAME, RUNNER_LABELS, RUNNER_TOKEN.
set -e
cd "${RUNNER_HOME:-$HOME}"
if [ ! -f .runner ]; then
  [ -n "${RUNNER_TOKEN:-}" ] || { echo "entrypoint: first start needs RUNNER_TOKEN (a registration token)" >&2; exit 1; }
  ./config.sh --url "${RUNNER_URL:-https://github.com/VytCepas/harbor}" --token "$RUNNER_TOKEN" \
    --name "${RUNNER_NAME:-harbor-linux}" --labels "${RUNNER_LABELS:-self-hosted,Linux,ARM64}" --no-default-labels \
    --work _work --unattended --replace
fi
unset RUNNER_TOKEN
exec ./run.sh
