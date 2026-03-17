FROM debian:trixie AS base

ARG REPOSITORY="pomerium/toolchain-utils"
ARG LLVM_VERSION
ARG RELEASE_REVISION

ARG TARGETARCH
RUN --mount=type=tmpfs,target=/var/cache/apt \
    --mount=type=tmpfs,target=/var/lib/apt/lists \
    --mount=type=tmpfs,target=/var/cache/debconf \
    apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates git curl \
 && apt-get clean \
 && curl -sfLo /usr/local/bin/bazelisk https://github.com/bazelbuild/bazelisk/releases/download/v1.28.1/bazelisk-linux-${TARGETARCH} \
 && chmod +x /usr/local/bin/bazelisk \
 && groupadd -g 1000 build \
 && useradd -m -u 1000 -g 1000 -s /bin/bash build

FROM base AS toolchain-setup

ADD --unpack=true https://github.com/${REPOSITORY}/releases/download/${LLVM_VERSION}-${RELEASE_REVISION}/llvm-${LLVM_VERSION}-minimal-linux-${TARGETARCH}.tar.zst /

RUN mv /llvm-${LLVM_VERSION}-minimal-linux-${TARGETARCH} /toolchain

# work around a bug(?) in toolchains_llvm that adds these lib64 directories to modulemap files,
# but these directories don't exist here
RUN mkdir -p /toolchain/lib64/clang/$(/toolchain/bin/clang -dumpversion | cut -d'.' -f1)/include \
 && mkdir -p /toolchain/lib64/clang/$(/toolchain/bin/clang -dumpversion)/include

FROM base

COPY --from=toolchain-setup /toolchain /toolchain
ENV BAZEL_LLVM_PATH=/toolchain

USER 1000:1000
