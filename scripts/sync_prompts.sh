#!/usr/bin/env bash
# 把 shared/prompts 复制到 iOS 核心库的资源目录。改完提示词后运行一次。
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/ios/NotBadCore/Sources/NotBadCore/Resources/prompts"
mkdir -p "$dest"
cp "$root"/shared/prompts/*.md "$dest"/
echo "已同步到 $dest"
