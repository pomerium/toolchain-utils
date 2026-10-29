FROM debian:trixie AS base

ARG TARGETARCH
RUN --mount=type=tmpfs,target=/var/cache/apt \
    --mount=type=tmpfs,target=/var/lib/apt/lists \
    --mount=type=tmpfs,target=/var/cache/debconf \
    apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    curl \
 && apt-get clean \
 && curl -sfLo /usr/local/bin/bazelisk https://github.com/bazelbuild/bazelisk/releases/download/v1.28.1/bazelisk-linux-${TARGETARCH} \
 && chmod +x /usr/local/bin/bazelisk \
 && groupadd -g 1000 build \
 && useradd -m -u 1000 -g 1000 -s /bin/bash build

USER 1000:1000
