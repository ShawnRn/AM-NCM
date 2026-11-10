#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ] || [ ! -d "$1" ] || [ "$(basename "$1")" != "AM-NCM.app" ] || [[ "$2" != *.dmg ]]; then
    echo "用法：bash Scripts/package-dmg.sh <AM-NCM.app 路径> <输出 .dmg 路径>" >&2
    exit 1
fi
if ! create-dmg --help 2>/dev/null | /usr/bin/grep -q -- '--no-version-in-filename'; then
    echo "请安装 npm 版 create-dmg（sindresorhus/create-dmg）。" >&2
    exit 1
fi

app="$(cd "$(dirname "$1")" && pwd)/AM-NCM.app"
output="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
if [ -e "$output" ]; then
    echo "输出文件已存在：$output" >&2
    exit 1
fi
codesign --verify --deep --strict "$app"
staging="$(mktemp -d "${TMPDIR:-/tmp}/am-ncm-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
cd "$staging"
create-dmg --no-version-in-filename --no-code-sign "$app" "$staging"
mv "$staging/AM-NCM.dmg" "$output"
