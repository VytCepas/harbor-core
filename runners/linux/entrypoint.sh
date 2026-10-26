#!/bin/sh
# Configure once (the registration token is only needed the first time), then run (harbor#1060).
# Contract with the provisioning lane: RUNNER_URL, RUNNER_NAME, RUNNER_LABELS, RUNNER_TOKEN.
set -e
cd "${RUNNER_HOME:-$HOME}"
if [ ! -f .runner ]; then
  [ -n "${RUNNER_TOKEN:-}" ] || { echo "entrypoint: first start needs RUNNER_TOKEN (a registration token)" >&2; exit 1; }  # secret-seam: container env (entry github-runner-registration)
  set -- --url "${RUNNER_URL:-https://github.com/VytCepas/harbor}" --token "$RUNNER_TOKEN"  # secret-seam: entry github-runner-registration
  ./config.sh "$@" \
    --name "${RUNNER_NAME:-harbor-linux}" --labels "${RUNNER_LABELS:-self-hosted,Linux,ARM64}" --no-default-labels \
    --work _work --unattended --replace
fi
unset RUNNER_TOKEN
# A self-update that died between moving bin/ aside and linking the new one leaves no Runner.Listener, and the
# restart policy turns that into a crash loop (harbor#1060, 2026-10-24: four containers, exit 127). Link the
# newest complete bin.<version> back; a real bin/ directory is never touched.
if [ ! -x bin/Runner.Listener ] && { [ ! -e bin ] || [ -L bin ]; }; then
  for _d in $(ls -d bin.* 2>/dev/null | sort -t. -k2,2nr -k3,3nr -k4,4nr); do
    [ -x "$_d/Runner.Listener" ] || continue
    rm -f bin; ln -s "$PWD/$_d" bin
    # externals follows bin: the interrupted update can leave a real externals/ half written (node24 with
    # no bin/node, estate-linux 2026-10-24), so it is moved aside, never deleted, and the version linked.
    if [ -d "externals.${_d#bin.}" ] && [ "$(readlink externals 2>/dev/null)" != "$PWD/externals.${_d#bin.}" ]; then
      [ ! -e externals ] || [ -L externals ] || mv externals "externals.interrupted-$$"
      rm -f externals; ln -s "$PWD/externals.${_d#bin.}" externals
    fi
    echo "entrypoint: bin/ had no Runner.Listener (an interrupted self-update); linked $_d" >&2
    break
  done
fi
exec ./run.sh
