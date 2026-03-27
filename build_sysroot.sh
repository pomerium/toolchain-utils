#!/bin/bash

set -eu -o pipefail

SCRIPT_DIR="$(realpath "$(dirname "$0")")"; readonly SCRIPT_DIR

temp="$(/bin/mktemp -d -p .)"

pushd "${temp}"

docker buildx build -f "${SCRIPT_DIR}/sysroot.dockerfile" \
  --platform linux/amd64,linux/arm64 \
  --output=type=local,dest=out \
  .

/bin/tar -cf "sysroot-linux-amd64.tar" -C out/ linux_amd64
/bin/zstd -T0 --long -10 --rm "sysroot-linux-amd64.tar"
/bin/mv "sysroot-linux-amd64.tar.zst" ..

/bin/tar -cf "sysroot-linux-arm64.tar" -C out/ linux_arm64
/bin/zstd -T0 --long -10 --rm "sysroot-linux-arm64.tar"
/bin/mv "sysroot-linux-arm64.tar.zst" ..


prefix="Payload/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"; readonly prefix
/bin/wget https://github.com/cerisier/pkgutil/releases/download/v1.2.0/pkgutil_linux_amd64
# obtained from https://swscan.apple.com/content/catalogs/others/index-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog
/bin/wget https://swcdn.apple.com/content/downloads/52/01/082-41241-A_0747ZN8FHV/dectd075r63pppkkzsb75qk61s0lfee22j/CLTools_macOSNMOS_SDK.pkg
/bin/sha256sum -c "${SCRIPT_DIR}/manifests/sysroot-macos.sha256"
/bin/chmod +x ./pkgutil_linux_amd64

/bin/mkdir -p out/macos_arm64

pushd ./out/macos_arm64
includes=()
while IFS=$'\n' read -r line; do
  includes+=("--include" "${prefix}/${line}")
done <"${SCRIPT_DIR}/manifests/sysroot-macos.txt"
../../pkgutil_linux_amd64 "${includes[@]}" --strip-components 6 --expand-full ../../CLTools_macOSNMOS_SDK.pkg .
popd

/bin/tar -cf "sysroot-macos-arm64.tar" -C out/ macos_arm64
/bin/zstd -T0 --long -10 --rm "sysroot-macos-arm64.tar"
/bin/mv "sysroot-macos-arm64.tar.zst" ..

popd
rm -rf "${temp}"
