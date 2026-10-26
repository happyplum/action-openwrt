#!/bin/bash
set -euo pipefail

# Xray 26.10.21 requires Go 1.27; pin the complete official build recipe.
golang_commit=0ee3fbc2992c75b2668933467479343c5e4c75e9
golang_dir=feeds/packages/lang/golang
mkdir -p tmp
scratch=$(mktemp -d tmp/pin-golang.XXXXXX)
trap 'rm -rf -- "$scratch"' EXIT

git -C feeds/packages fetch --depth=1 https://github.com/immortalwrt/packages.git "$golang_commit"
# Fresh mtimes make OpenWrt regenerate metadata cached before this replacement.
git -C feeds/packages archive "$golang_commit" lang/golang | tar -xm -C "$scratch"
grep -Fxq 'GO_DEFAULT_VERSION:=1.27' "$scratch/lang/golang/golang-values.mk"
grep -Fxq 'GO_VERSION_MAJOR_MINOR:=1.27' "$scratch/lang/golang/golang1.27/Makefile"
grep -Fxq 'GO_VERSION_PATCH:=2' "$scratch/lang/golang/golang1.27/Makefile"

# Remove only installed links owned by the Go directory, including the old 1.26 package.
golang_path=$(realpath "$golang_dir")
for link in package/feeds/packages/*; do
    [[ -L "$link" ]] || continue
    case "$(realpath -m "$link")" in
        "$golang_path"/*) rm -- "$link" ;;
    esac
done
rm -rf -- "$golang_dir"
mv -- "$scratch/lang/golang" "$golang_dir"

./scripts/feeds update -i packages
# feeds update does not propagate every indexing error; check its actual output.
grep -Fxq 'Source-Makefile: feeds/packages/lang/golang/golang1.27/Makefile' feeds/packages.index
grep -A1 -Fx 'Source-Makefile: feeds/packages/lang/golang/golang/Makefile' feeds/packages.index |
    grep -Fxq 'Build-Depends/host: golang1.27/host'
grep -Fxq 'Source: go1.27.2.src.tar.gz' feeds/packages.index
./scripts/feeds install -p packages golang golang1.27
for package in golang golang1.27 golang-bootstrap; do
    link="package/feeds/packages/$package"
    [[ -L "$link" && -f "$link/Makefile" ]]
    [[ "$(realpath "$link")" == "$golang_path/$package" ]]
done
echo "Pinned OpenWrt Go 1.27.2: $golang_commit"
