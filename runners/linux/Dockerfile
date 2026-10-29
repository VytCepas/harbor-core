# The self-hosted Linux runner image (harbor#1060): what harbor's suites and the fleet's setup actions
# (setup-uv, setup-python, setup-bun) need, so no job installs anything. Build: docker build -t port-linux-runner:local runners/linux
FROM ghcr.io/actions/actions-runner:latest
USER root
ARG NODE_VERSION=24.21.0
ARG GITLEAKS_VERSION=8.24.3
ARG GH_VERSION=2.102.0
ARG BUN_VERSION=1.4.2
# node (below): bin/browser-*.mjs and tests/cli/browser-test.sh. bun: tests/cli/console-guards-test.sh and console-panels-test.sh (harbor#738), and the memory engine. gh: scaffolded validate-pr jobs and project-init's
# tests (hosted runners ship it). gitleaks >= 8.19 has `gitleaks git`, which the scaffold's pre-commit hook calls. xz-utils, zstd, unzip: unpacking toolchains and caches.
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends jq dash shellcheck git perl gawk curl ca-certificates python3 procps util-linux file xz-utils unzip zstd \
 && rm -rf /var/lib/apt/lists/*
# Pinned and checksummed per architecture: the runner is arm64 on the Mac, x64 on a hosted fallback.
RUN set -eu; arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      arm64) node_arch=arm64; node_sha=6ad1325edbdb5649c379b75a237147a666c95d4f9ae8d340fef2d1575d289ad2; gl_arch=arm64; gl_sha=5f2edbe1f49f7b920f9e06e90759947d3c5dfc16f752fb93aaafc17e9d14cf07; gh_arch=arm64; gh_sha=7862c86c72f43df3a2d93ddde6f473285b4e2af61b494849846827e513ef6484; bun_arch=aarch64; bun_sha=54328bbc2d9c8e0c9f892c544d66c57a83b84139e34909e5ee81758f1ac8fda7 ;; \
      amd64) node_arch=x64;   node_sha=fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6; gl_arch=x64;   gl_sha=9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c; gh_arch=amd64; gh_sha=bb766f710eef8ede859c18578c72c327597cd4c8a85b06001b1f3843c6019386; bun_arch=x64; bun_sha=36368faef7527875d5ffa52e53cd48021741f2a83eb6208a8dd64068d422a913 ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" -o /tmp/node.tar.xz; \
    echo "${node_sha}  /tmp/node.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE'; \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz" -o /tmp/gl.tar.gz; \
    echo "${gl_sha}  /tmp/gl.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gl.tar.gz -C /usr/local/bin gitleaks; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${gh_arch}.tar.gz" -o /tmp/gh.tar.gz; \
    echo "${gh_sha}  /tmp/gh.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gh.tar.gz -C /usr/local/bin --strip-components=2 "gh_${GH_VERSION}_linux_${gh_arch}/bin/gh"; \
    curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${bun_arch}.zip" -o /tmp/bun.zip; \
    echo "${bun_sha}  /tmp/bun.zip" | sha256sum -c -; \
    unzip -q -j /tmp/bun.zip "bun-linux-${bun_arch}/bun" -d /usr/local/bin; chmod 755 /usr/local/bin/bun; \
    rm -f /tmp/node.tar.xz /tmp/gl.tar.gz /tmp/gh.tar.gz /tmp/bun.zip
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh
# The image promises node: browser-test fails here, instead of skipping, if it goes missing (harbor#1060).
ENV HARBOR_REQUIRE_NODE=1
USER runner
ENTRYPOINT ["/entrypoint.sh"]
