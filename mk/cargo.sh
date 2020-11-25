#!/usr/bin/env bash
#
# Copyright 2020 Brian Smith.
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHORS DISCLAIM ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY
# SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
# OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
# CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

set -eux -o pipefail
IFS=$'\n\t'

rustflags_self_contained="-Clink-self-contained=yes -Clinker=rust-lld"
qemu_aarch64="qemu-aarch64 -L /usr/aarch64-linux-gnu"
qemu_arm="qemu-arm -L /usr/arm-linux-gnueabihf"

# Avoid putting the Android tools in `$PATH` because there are tools in this
# directory like `clang` that would conflict with the same-named tools that may
# be needed to compile the build script, or to compile for other targets.
if [ -n "${ANDROID_SDK_ROOT-}" ]; then
  android_tools=$ANDROID_SDK_ROOT/ndk-bundle/toolchains/llvm/prebuilt/linux-x86_64/bin
fi

for arg in $*; do
  case $arg in
    --target=*)
      target=${arg#*=}
      ;;
    *)
      ;;
  esac
done

case $target in
   aarch64-linux-android)
    export CC_aarch64_linux_android=$android_tools/aarch64-linux-android21-clang
    export AR_aarch64_linux_android=$android_tools/aarch64-linux-android-ar
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=$android_tools/aarch64-linux-android21-clang
    ;;
  aarch64-unknown-linux-gnu)
    export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
    export AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc-ar
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUNNER="$qemu_aarch64"
    ;;
  aarch64-unknown-linux-musl)
    export CC_aarch64_unknown_linux_musl=clang-10
    export AR_aarch64_unknown_linux_musl=llvm-ar-10
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_RUSTFLAGS="$rustflags_self_contained"
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_RUNNER="$qemu_aarch64"
    ;;
  arm-unknown-linux-gnueabihf)
    export CC_arm_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc
    export AR_arm_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc-ar
    export CARGO_TARGET_ARM_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc
    export CARGO_TARGET_ARM_UNKNOWN_LINUX_GNUEABIHF_RUNNER="$qemu_arm"
    ;;
  armv7-linux-androideabi)
    export CC_armv7_linux_androideabi=$android_tools/armv7a-linux-androideabi18-clang
    export AR_armv7_linux_androideabi=$android_tools/arm-linux-androideabi-ar
    export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER=$android_tools/armv7a-linux-androideabi18-clang
    ;;
  armv7-unknown-linux-musleabihf)
    export CC_armv7_unknown_linux_musleabihf=clang-10
    export AR_armv7_unknown_linux_musleabihf=llvm-ar-10
    export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_RUSTFLAGS="$rustflags_self_contained"
    export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_RUNNER="$qemu_arm"
    ;;
  i686-unknown-linux-gnu)
    export CC_i686_unknown_linux_gnu=clang-10
    export AR_i686_unknown_linux_gnu=llvm-ar-10
    export CARGO_TARGET_I686_UNKNOWN_LINUX_GNU_LINKER=clang-10
    ;;
  i686-unknown-linux-musl)
    export CC_i686_unknown_linux_musl=clang-10
    export AR_i686_unknown_linux_musl=llvm-ar-10
    export CARGO_TARGET_I686_UNKNOWN_LINUX_MUSL_LINKER=clang-10
    ;;
  x86_64-unknown-linux-musl)
    export CC_x86_64_unknown_linux_musl=clang-10
    export AR_x86_64_unknown_linux_musl=llvm-ar-10
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=clang-10
    ;;
  wasm32-unknown-unknown)
    # The first two are only needed for when the "wasm_c" feature is enabled.
    export CC_wasm32_unknown_unknown=clang-10
    export AR_wasm32_unknown_unknown=llvm-ar-10
    export CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUNNER=wasm-bindgen-test-runner
    ;;
  *)
    ;;
esac

if [ -n "${RING_COVERAGE-}" ]; then
  # XXX: Collides between release and debug.
  coverage_dir=$PWD/target/$target/debug/coverage
  mkdir -p "$coverage_dir"
  rm -f "$coverage_dir/*.profraw"

  export RING_BUILD_EXECUTABLE_LIST="$coverage_dir/executables"
  truncate --size=0 "$RING_BUILD_EXECUTABLE_LIST"

  export LLVM_PROFILE_FILE="$coverage_dir/%m.profraw"

  # ${target} with hyphens replaced by underscores, lowercase and uppercase.
  target_lower=${target//-/_}
  target_upper=${target_lower^^}
  runner_var=CARGO_TARGET_${target_upper}_RUNNER
  declare -x "${runner_var}=mk/runner ${!runner_var-}"

  rustflags_var=CARGO_TARGET_${target_upper}_RUSTFLAGS
  declare -x "${rustflags_var}=-Zinstrument-coverage ${!rustflags_var-}"
fi

cargo "$@"

if [ -n "$RING_COVERAGE" ]; then
  llvm-profdata-10 merge -sparse "$coverage_dir"/*.profraw -o "$coverage_dir/merged.profdata"
  xargs --arg-file="$RING_BUILD_EXECUTABLE_LIST" \
    llvm-cov-10 show -instr-profile="$coverage_dir/merged.profdata" \
    > "$coverage_dir"/coverage.txt
fi
