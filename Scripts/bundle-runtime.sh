#!/bin/bash
set -euo pipefail

version=26.3.1
case "${NATIVE_ARCH_ACTUAL:-$(uname -m)}" in
    arm64) arch=arm64; checksum=3f624ab0d774553c0d28b968e141d8c676a35a2811fb0b7b356ba9cbdce15f74 ;;
    x86_64) arch=x64; checksum=3ec9e5a28c641c088f3d04ad38721bfdedb2f8aa8c031979fa93df08b5a92e58 ;;
    *) echo "Unsupported Node runtime architecture" >&2; exit 1 ;;
esac
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cache="${DERIVED_FILE_DIR}/am-ncm-runtime"
archive="node-v${version}-darwin-${arch}"
mkdir -p "$cache"
if [ ! -x "$cache/$archive/bin/node" ]; then
    curl -fsSL "https://nodejs.org/dist/v$version/$archive.tar.gz" -o "$cache/$archive.tar.gz"
    printf '%s  %s\n' "$checksum" "$cache/$archive.tar.gz" | shasum -a 256 -c -
    tar -xzf "$cache/$archive.tar.gz" -C "$cache"
fi

dependencies="$cache/dependencies"
mkdir -p "$dependencies"
if ! cmp -s "$SRCROOT/package-lock.json" "$dependencies/installed-lock.json"; then
    cp "$SRCROOT/package.json" "$SRCROOT/package-lock.json" "$dependencies/"
    (cd "$dependencies"; "$cache/$archive/bin/node" "$cache/$archive/lib/node_modules/npm/bin/npm-cli.js" ci --ignore-scripts --omit=dev --no-audit --no-fund)
    cp "$SRCROOT/package-lock.json" "$dependencies/installed-lock.json"
fi

engine="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Engine"
helpers="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
mkdir -p "$engine" "$helpers"
cp "$cache/$archive/bin/node" "$helpers/node"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$helpers/node"
cp "$cache/$archive/LICENSE" "$engine/Node-LICENSE"
cp "$SRCROOT/"{ncm.cjs,sync.cjs,scan.cjs,music-scan.js} "$engine/"
rsync -a --delete --exclude=.bin "$dependencies/node_modules/" "$engine/node_modules/"
