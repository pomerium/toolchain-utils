FROM debian:trixie AS base

ARG REPOSITORY="pomerium/toolchain-utils"
ARG LLVM_VERSION
ARG RELEASE_REVISION

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

FROM base AS toolchain-setup

ADD --unpack=true https://github.com/${REPOSITORY}/releases/download/${LLVM_VERSION}-${RELEASE_REVISION}/llvm-${LLVM_VERSION}-minimal-linux-${TARGETARCH}.tar.zst /

RUN mv /llvm-${LLVM_VERSION}-minimal-linux-${TARGETARCH} /toolchain

# work around a bug(?) in toolchains_llvm that adds these lib64 directories to modulemap files,
# but these directories don't exist here
RUN mkdir -p /toolchain/lib64/clang/$(/toolchain/bin/clang -dumpversion | cut -d'.' -f1)/include \
 && mkdir -p /toolchain/lib64/clang/$(/toolchain/bin/clang -dumpversion)/include

# In normal circumstances, toolchains_llvm will link files listed in the libclang_rt
# and cxx_cross_libs attributes into the toolchain root. It does not do this when
# overriding the toolchain root, so we need to copy the files ourselves

ADD --unpack=true https://github.com/${REPOSITORY}/releases/download/${LLVM_VERSION}-${RELEASE_REVISION}/cxx-cross-libs-${LLVM_VERSION}-linux-arm64.tar.zst /tmp
ADD --unpack=true https://github.com/${REPOSITORY}/releases/download/${LLVM_VERSION}-${RELEASE_REVISION}/cxx-cross-libs-${LLVM_VERSION}-macos-arm64.tar.zst /tmp

# we should end up with a directory structure like this:
# /toolchain
#   /lib
#      /x86_64-unknown-linux-gnu/{everything for x86_64}
#      /aarch64-unknown-linux-gnu/{libc++.a,libc++abi.a,libunwind.a}
#      /aarch64-apple-macosx/{libc++.a,libc++abi.a,libunwind.a}
#      /clang/##/lib
#         /x86_64-unknown-linux-gnu/{everything for x86_64}
#         /aarch64-unknown-linux-gnu/{libclang_rt.builtins.a,clang_rt.crtbegin.o,clang_rt.crtend.o}
#         /aarch64-apple-macosx/{libclang_rt.osx.a}
#   /include
#      /c++/v1/{everything for x86_64}
#      /x86_64-unknown-linux-gnu/c++/v1/__config_site
#      /aarch64-unknown-linux-gnu/c++/v1/__config_site
#      /aarch64-apple-macosx/c++/v1/__config_site

RUN export CLANG_VERSION_MAJOR="$(/toolchain/bin/clang -dumpversion | cut -d'.' -f1)"; \
    mkdir -p /toolchain/include/aarch64-unknown-linux-gnu/c++/v1 \
 && cp /tmp/cxx-cross-libs-${LLVM_VERSION}-linux-arm64/include/aarch64-unknown-linux-gnu/c++/v1/* /toolchain/include/aarch64-unknown-linux-gnu/c++/v1/ \
 && mkdir -p /toolchain/lib/clang/${CLANG_VERSION_MAJOR}/lib/aarch64-unknown-linux-gnu \
 && cp /tmp/cxx-cross-libs-${LLVM_VERSION}-linux-arm64/lib/clang/${CLANG_VERSION_MAJOR}/lib/aarch64-unknown-linux-gnu/* /toolchain/lib/clang/${CLANG_VERSION_MAJOR}/lib/aarch64-unknown-linux-gnu/ \
 && mkdir -p /toolchain/lib/aarch64-unknown-linux-gnu \
 && cp /tmp/cxx-cross-libs-${LLVM_VERSION}-linux-arm64/lib/aarch64-unknown-linux-gnu/*.a /toolchain/lib/aarch64-unknown-linux-gnu/ \
 && mkdir -p /toolchain/include/aarch64-apple-macosx/c++/v1 \
 && cp /tmp/cxx-cross-libs-${LLVM_VERSION}-macos-arm64/include/c++/v1/* /toolchain/include/aarch64-apple-macosx/c++/v1/ \
 && mkdir -p /toolchain/lib/clang/${CLANG_VERSION_MAJOR}/lib/aarch64-apple-macosx \
 && cp /tmp/cxx-cross-libs-${LLVM_VERSION}-macos-arm64/lib/clang/${CLANG_VERSION_MAJOR}/lib/darwin/* /toolchain/lib/clang/${CLANG_VERSION_MAJOR}/lib/aarch64-apple-macosx/ \
 && mkdir -p /toolchain/lib/aarch64-apple-macosx \
 && cp /tmp/cxx-cross-libs-${LLVM_VERSION}-macos-arm64/lib/*.a /toolchain/lib/aarch64-apple-macosx/

FROM base

COPY --from=toolchain-setup /toolchain /toolchain
ENV BAZEL_LLVM_PATH=/toolchain

USER 1000:1000
