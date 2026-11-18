#!/bin/bash
set -eu

# Call before pin-golang.sh regenerates the feed index.
rust_makefile=feeds/packages/lang/rust/Makefile
rust_version=$(sed -n 's/^PKG_VERSION:=//p' "$rust_makefile")
if [[ "$rust_version" == 1.96.0 ]]; then
    # Backport immortalwrt/packages@1d995816 so Rust can download its prebuilt LLVM again.
    sed -i \
        -e 's/^PKG_VERSION:=.*/PKG_VERSION:=1.96.1/' \
        -e 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/' \
        -e 's/^PKG_HASH:=.*/PKG_HASH:=77a6ff3003a4ad0cb00697b043c879e3e1a15d945b1a1f63818903bfc3fa8b98/' \
        "$rust_makefile"
fi
