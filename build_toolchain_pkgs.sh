#!/bin/bash

set -u

function die() {
  echo "$*" | tee .err
  exit 1
}

readonly LLVM_VERSION

if [ -z "${LLVM_VERSION}" ]; then
  echo "missing LLVM_VERSION environment variable"
  exit 1
fi

LLVM_VERSION_MAJOR="$(/bin/echo "${LLVM_VERSION}" | /bin/cut -d '.' -f 1)"; readonly LLVM_VERSION_MAJOR
LLVM_VERSION_MINOR="$(/bin/echo "${LLVM_VERSION}" | /bin/cut -d '.' -f 2)"; readonly LLVM_VERSION_MINOR
LLVM_VERSION_PATCH="$(/bin/echo "${LLVM_VERSION}" | /bin/cut -d '.' -f 3)"; readonly LLVM_VERSION_PATCH
SCRIPT_DIR="$(realpath "$(dirname "$0")")"; readonly SCRIPT_DIR

function download_extract() (
  local os_arch="$1"
  /bin/wget -q "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/LLVM-${LLVM_VERSION}-${os_arch}.tar.xz" || die "error downloading llvm tarball"
  /bin/wget -q "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/LLVM-${LLVM_VERSION}-${os_arch}.tar.xz.sig" || die "error downloading llvm tarball signature"
  /bin/gpg -q --verify "LLVM-${LLVM_VERSION}-${os_arch}.tar.xz.sig" "LLVM-${LLVM_VERSION}-${os_arch}.tar.xz" || die "gpg verify failed"
  /bin/unxz -T0 "LLVM-${LLVM_VERSION}-${os_arch}.tar.xz" || die "failed to extract llvm tarball"
)

function generate_manifest() (
  local os_arch="$1"
  local triple="$2"
  local tpl_basename="$3"

  local input_tpl; input_tpl="${SCRIPT_DIR}/manifests/${tpl_basename}-$(echo -n "$os_arch" | cut -d '-' -f 1 | tr '[:upper:]' '[:lower:]').tpl"
  local output; output="${tpl_basename}-${os_arch}.manifest.txt"
  /bin/cat "${input_tpl}"  \
    | /bin/sed -e "s/{triple}/${triple}/g" \
          -e "s/{prefix}/LLVM-${LLVM_VERSION}-${os_arch}/g" \
          -e "s/{version_major}/${LLVM_VERSION_MAJOR}/g" \
          -e "s/{version_minor}/${LLVM_VERSION_MINOR}/g" \
          -e "s/{version_patch}/${LLVM_VERSION_PATCH}/g" \
    > "${output}"
)

function extract_from_manifest() (
  local os_arch="$1"
  local manifest="$2"
  local src="$3"
  /bin/tar -x  --files-from "${manifest}" -f "${src}" || die "failed to extract files from manifest (os_arch=${os_arch}; manifest=${manifest}; src=${src})"
)


function build_archive() (
  local os_arch="$1"
  local triple="$2"
  local tpl_basename="$3"
  local out_basename="$4"
  local compression_level="${5:-10}"
  local temp; temp="$(/bin/mktemp -d -p .)"

  pushd "${temp}" || exit 1

  generate_manifest "${os_arch}" "${triple}" "${tpl_basename}"
  extract_from_manifest "${os_arch}" "${tpl_basename}-${os_arch}.manifest.txt" "../srcs/LLVM-${LLVM_VERSION}-${os_arch}.tar"
  /bin/mv "LLVM-${LLVM_VERSION}-${os_arch}" "${out_basename}"
  /bin/tar -cf "${out_basename}.tar" "${out_basename}"
  /bin/zstd -T0 --long -"${compression_level}" --rm "${out_basename}.tar"
  /bin/mv "${out_basename}.tar.zst" ..

  popd || exit 1

  /bin/rm -r "${temp}"
)

mkdir srcs
pushd srcs || exit 1
rm -f .err
download_extract "Linux-X64" || die "download_extract failed (Linux-X64)" &
download_extract "Linux-ARM64" || die "download_extract failed (Linux-ARM64)" &
download_extract "macOS-ARM64" || die "download_extract failed (macOS-ARM64)" &
wait
[[ ! -f ".err" ]] || exit 1
popd || exit 1

rm -f .err
build_archive "Linux-X64" "x86_64-unknown-linux-gnu" "llvm" "llvm-${LLVM_VERSION}-minimal-linux-amd64" || die "build_archive failed (Linux-X64)" &
build_archive "Linux-ARM64" "aarch64-unknown-linux-gnu" "llvm" "llvm-${LLVM_VERSION}-minimal-linux-arm64" || die "build_archive failed (Linux-ARM64)" &
build_archive "macOS-ARM64" "" "llvm" "llvm-${LLVM_VERSION}-minimal-macos-arm64" || die "build_archive failed (macOS-ARM64)" &
build_archive "Linux-ARM64" "aarch64-unknown-linux-gnu" "cxx-cross-libs" "cxx-cross-libs-${LLVM_VERSION}-linux-arm64" "19" || die "build_archive failed (Linux-ARM64)" &
build_archive "macOS-ARM64" "" "cxx-cross-libs" "cxx-cross-libs-${LLVM_VERSION}-macos-arm64" "19" || die "build_archive failed (macOS-ARM64)" &
build_archive "Linux-X64" "x86_64-unknown-linux-gnu" "llvm-extras" "llvm-extras-${LLVM_VERSION}-linux-amd64" || die "build_archive failed (Linux-X64)" &
build_archive "Linux-ARM64" "aarch64-unknown-linux-gnu" "llvm-extras" "llvm-extras-${LLVM_VERSION}-linux-arm64" || die "build_archive failed (Linux-ARM64)" &
wait
[[ ! -f ".err" ]] || exit 1


# some compression benchmarks for fun
# (adding --long gave better results in all cases)
# $ zstd -T0 --progress -b -e22 --long LLVM-22.1.1-Linux-X64.tar
#  3#1.1-Linux-X64.tar :1205237760 -> 272621813 (x4.421),  752.5 MB/s, 1128.9 MB/s
#  4#1.1-Linux-X64.tar :1205237760 -> 269362144 (x4.474),  878.2 MB/s, 1116.3 MB/s
#  5#1.1-Linux-X64.tar :1205237760 -> 262668936 (x4.588),  786.2 MB/s, 1114.7 MB/s
#  6#1.1-Linux-X64.tar :1205237760 -> 254002096 (x4.745),  777.6 MB/s, 1159.1 MB/s
#  7#1.1-Linux-X64.tar :1205237760 -> 249301036 (x4.834),  827.0 MB/s, 1164.0 MB/s
#  8#1.1-Linux-X64.tar :1205237760 -> 247231927 (x4.875),  705.8 MB/s, 1185.0 MB/s
#  9#1.1-Linux-X64.tar :1205237760 -> 243937019 (x4.941),  869.0 MB/s, 1178.7 MB/s
# 10#1.1-Linux-X64.tar :1205237760 -> 239732006 (x5.027),  641.6 MB/s, 1164.6 MB/s
# 11#1.1-Linux-X64.tar :1205237760 -> 239109649 (x5.041),  464.5 MB/s, 1197.0 MB/s
# 12#1.1-Linux-X64.tar :1205237760 -> 236365123 (x5.099),  308.3 MB/s, 1116.7 MB/s
# 13#1.1-Linux-X64.tar :1205237760 -> 238165849 (x5.060),  290.9 MB/s, 1173.6 MB/s
# 14#1.1-Linux-X64.tar :1205237760 -> 237913824 (x5.066),  251.1 MB/s, 1180.7 MB/s
# 15#1.1-Linux-X64.tar :1205237760 -> 235166432 (x5.125),  140.3 MB/s, 1152.9 MB/s
# 16#1.1-Linux-X64.tar :1205237760 -> 228360139 (x5.278),  158.2 MB/s, 1044.7 MB/s
# 17#1.1-Linux-X64.tar :1205237760 -> 223511006 (x5.392),   77.9 MB/s, 1026.4 MB/s
# 18#1.1-Linux-X64.tar :1205237760 -> 213246225 (x5.652),   69.9 MB/s,  931.7 MB/s
# 19#1.1-Linux-X64.tar :1205237760 -> 208517975 (x5.780),   29.6 MB/s,  905.6 MB/s
# 20#1.1-Linux-X64.tar :1205237760 -> 199775098 (x6.033),   14.2 MB/s,  916.9 MB/s
# 21#1.1-Linux-X64.tar :1205237760 -> 195579774 (x6.162),   7.84 MB/s,  916.4 MB/s
# 22#1.1-Linux-X64.tar :1205237760 -> 192333422 (x6.266),   3.53 MB/s,  920.5 MB/s
