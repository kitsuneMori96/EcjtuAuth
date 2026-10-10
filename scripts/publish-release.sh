#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?用法: $0 <version>  例如: 1.1.1}"
REPO="kitsuneMori96/EcjtuAuth"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR=$(mktemp -d)

echo "📦 发布 ${VERSION} → ${REPO}"

# ─── 查找最新 Build 运行 ─────────────────────────────
RUN_ID=$(gh run list --repo "$REPO" --workflow "Build" --limit 20 \
  --json databaseId,headBranch,status,conclusion \
  --jq "[.[] | select(.headBranch == \"${VERSION}\" and .status == \"completed\" and .conclusion == \"success\")][0].databaseId" 2>/dev/null)

# 如果没找到（tag 可能不是分支名），用最新成功的 Build
if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
  RUN_ID=$(gh run list --repo "$REPO" --workflow "Build" --limit 5 \
    --json databaseId,status,conclusion \
    --jq "[.[] | select(.status == \"completed\" and .conclusion == \"success\")][0].databaseId")
fi

if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
  echo "❌ 找不到成功的 Build 运行"
  exit 1
fi

echo "🔧 使用 Build run: ${RUN_ID}"

# ─── 下载 artifacts ──────────────────────────────────
cd "$WORK_DIR"
gh run download "$RUN_ID" --repo "$REPO" --dir artifacts
echo "📥 Artifact 已下载"
ls -la artifacts/

# ─── 查找文件 ────────────────────────────────────────
WIN_ZIP=$(find artifacts -name "*windows*.zip" | head -1)
APK=$(find artifacts -name "*.apk" | head -1)

if [[ -z "$WIN_ZIP" ]]; then
  echo "❌ 未找到 Windows artifact"
  exit 1
fi

# ─── 删除旧 release（如果存在）──────────────────────
if gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  echo "🗑️ 删除旧 release ${VERSION}"
  gh release delete "$VERSION" --repo "$REPO" --yes
fi

# ─── 创建 release ────────────────────────────────────
ARGS=(
  --repo "$REPO"
  --title "v${VERSION}"
  --prerelease
  --notes-file "${REPO_DIR}/CHANGELOG.md"
  "$WIN_ZIP"
)

if [[ -n "$APK" ]]; then
  ARGS+=("$APK")
fi

gh release create "$VERSION" "${ARGS[@]}"

echo ""
echo "✅ v${VERSION} 已发布"
echo "🔗 https://github.com/${REPO}/releases/tag/v${VERSION}"

# ─── 清理 ────────────────────────────────────────────
rm -rf "$WORK_DIR"
