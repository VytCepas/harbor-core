# docs/reference/runtime.md — local containers, Kubernetes, and GCP parity

What to use on the workstation, and the four places where "it worked locally"
stops predicting the cloud. Machine state is a claim: measured 2026-08-21,
re-measure rather than trust this file.

## Use Colima

**Colima (MIT) + the real Docker CLI, engine and compose plugin.** Colima
replaces *Docker Desktop* — the VM manager — not Docker. The daemon inside the
VM is genuine Docker Engine, so every `docker` and `docker compose` command is
the documented one.

- Config that earns its keep: `--vm-type vz --mount-type virtiofs`, arm64 native.
- **Docker Desktop** is absent by decision: paid for companies past its size
  threshold, and it buys nothing Colima lacks except a GUI and Extensions.
- **OrbStack** is the nicer product and is **not free for company work** — its
  free tier reads "Personal, non-commercial use"; commercial is per-seat monthly.
- **Podman / Rancher Desktop** work but are both VM-backed on macOS too: a
  rewrite of compose usage for no measured gain.
- **Apple `container`** is worth watching, not adopting: no compose, arm64-only,
  no Docker socket, so anything shelling out to `docker` breaks.

## Kubernetes, locally

Two routes, both free:

- **kind** — throwaway clusters, node-image version pinning. Also what `abctl`
  drives, so an abctl-deployed stack can be reproduced locally instead of being
  debugged in prod.
- **`colima start --kubernetes`** — k3s inside the VM, one standing cluster,
  kubeconfig written for you.

`helm` is not installed; install it before real chart work. The VM ships with a
fraction of the host's cores and RAM, which is enough for one small cluster and
not enough for a full application stack — raise `--cpu/--memory` before blaming
Kubernetes.

**Local is API-surface parity, never platform parity.** Workload Identity,
GCLB/Ingress, PD and Filestore CSI, and Autopilot admission have no local
equivalent. Anything touching identity or load balancing is proven on a real
cluster or it is not proven.

**And there is no cluster to be parity *with*.** Measured 2026-08-21 across every
project the estate can see: the Kubernetes Engine API is enabled in **none** of
them — the API answers "has not been used in project … before", which is stronger
than an empty cluster list. The deployment surface is Cloud Run, Artifact Registry
and Cloud Build. So local Kubernetes earns its place for reproducing an
abctl-deployed stack, and for learning, and not yet for prod parity.

## The four GCP seams

1. **Architecture — the one that bites.** Cloud Run requires Linux x86_64;
   arm64 images are not supported, and a multi-arch manifest "must include
   `linux/amd64`". Colima on Apple Silicon builds **arm64 by default**, so a
   locally-built image fails to start in Cloud Run with an exec-format error.
   Build `--platform linux/amd64` (this box's buildx advertises amd64, arm64 and
   386) or build in Cloud Build. Same trap on any amd64 GKE node pool.
2. **Identity.** Both sides authenticate through ADC, so the code path is
   already identical — the *principal* is not. Locally that is a human
   credential with human permissions; in cloud it is the runtime service
   account. Close it by impersonating that service account
   (`gcloud auth application-default login --impersonate-service-account=…`),
   not by widening the human. Mount ADC read-only; never bake a key into an
   image. Note there is no single runtime principal to impersonate, and the
   estate is **mixed**: some services carry a dedicated account, some share one
   across a couple of services, and several still run as the project's
   **default compute service account**. Parity is therefore chosen per service
   under test, and "it worked locally" is scoped to the one you picked.
   Impersonating a default compute account is the case to think twice about — it
   is broad by construction, so local parity with it hands a test whatever that
   account can reach.
3. **Registry.** One command wires the Docker client to Artifact Registry through
   the credential helper that ships with the SDK, and it works under Colima
   unchanged:

   ```
   gcloud auth configure-docker REGION-docker.pkg.dev
   ```

   **Wired on this box on 2026-08-21** for every region the estate actually keeps
   repositories in, and verified against a private image rather than assumed.
   **The gotcha is worth more than the command:** the helper resolves its account
   from whatever gcloud config directory is exported *when docker runs*, not from
   the login that configured it. Same inspect call, same image, exported identity
   directory versus none:

   | Probe | Result |
   |---|---|
   | with the identity directory exported | manifest returned |
   | without it | `(gcloud.auth.docker-helper) Reauthentication failed` |

   So a `push` from a shell that has not exported it fails against a stale
   default config, and the error names gcloud, not docker.
4. **Promotion.** Build once, push once, deploy **by digest, not by tag**. A tag
   is a moving pointer, so tag-based promotion means local and cloud can run
   different bytes while every log line agrees. Note that buildx attaches
   provenance attestations by default, so even a single-platform build produces a
   manifest *list* — pass `--provenance=false` when a bare image digest is what
   the deploy step expects.

**No warehouse emulator exists.** Warehouse work is developed against a real
dataset under a dev prefix; that seam does not close locally, and pretending
otherwise is how a query passes locally and costs money in prod.

## Disk

Deleting images returns nothing to macOS. The VM's data disk is a sparse file:
the guest frees blocks, the host keeps them. Reclaim with

    colima ssh -- sudo fstrim -av

which returned 23.5 GiB the first time it was ever run here. Nothing does this
on a schedule — if disk is missing and `docker system df` looks innocent, this
is why.
