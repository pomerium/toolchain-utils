FROM debian:trixie AS base

# Note: the libxml2 package in ubuntu has an additional dependency on libicu74,
# but the debian version does not. If you run ldd or objdump -P on ld.lld from
# an ubuntu host for example, it will show libicuuc.so.74 and libicudata.so.74
# as needed.

ARG TARGETARCH
RUN --mount=type=tmpfs,target=/var/cache/apt \
    --mount=type=tmpfs,target=/var/lib/apt/lists \
    --mount=type=tmpfs,target=/var/cache/debconf \
    apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    curl \
    libxml2 \
 && apt-get clean \
 && curl -sfLo /usr/local/bin/bazelisk https://github.com/bazelbuild/bazelisk/releases/download/v1.28.1/bazelisk-linux-${TARGETARCH} \
 && chmod +x /usr/local/bin/bazelisk \
 && groupadd -g 1000 build \
 && useradd -m -u 1000 -g 1000 -s /bin/bash build

USER 1000:1000
