#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# ─── 参数解析 ─────────────────────────────────────────
BUMP="${1:-}"
SUFFIX="${2:---stable}"

if [[ "$BUMP" != "major" && "$BUMP" != "minor" && "$BUMP" != "patch" ]]; then
  echo "用法: $0 [major|minor|patch] [--beta|--stable]"
  exit 1
fi

# ─── 前置检查 ─────────────────────────────────────────
if [[ -n "$(git status --porcelain)" ]]; then
  echo "错误: 工作区不干净，请先 commit 或 stash"
  git status --short
  exit 1
fi

# ─── 读取当前版本 ─────────────────────────────────────
CUR=$(grep '^version:' pubspec.yaml | awk '{print $2}')
BASE=$(echo "$CUR" | sed 's/-beta\.[0-9]*//' | sed 's/+.*//')
IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE"

# ─── 递增版本号 ───────────────────────────────────────
case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# beta 后缀
if [[ "$SUFFIX" == "--beta" ]]; then
  # 找当前最大 beta 号
  BETA_N=$(echo "$CUR" | grep -oP 'beta\.\K[0-9]+' || echo "0")
  NEW_VERSION="${NEW_VERSION}-beta.$((BETA_N + 1))"
fi

# 构建号递增
BUILD_N=$(echo "$CUR" | grep -oP '\+\K[0-9]+' || echo "0")
NEW_VERSION="${NEW_VERSION}+$((BUILD_N + 1))"

echo "版本: $CUR → $NEW_VERSION"

# ─── 更新 pubspec.yaml ───────────────────────────────
sed -i "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml

# ─── 更新 CHANGELOG.md ───────────────────────────────
TAG_VERSION=$(echo "$NEW_VERSION" | sed 's/+.*//')
TODAY=$(date +%Y-%m-%d)
HEADING="## ${TAG_VERSION} - ${TODAY}"

if grep -q "^## ${TAG_VERSION}" CHANGELOG.md; then
  echo "CHANGELOG 已有 ${TAG_VERSION} 条目，跳过插入"
else
  # 在第一个 ## 标题前插入新条目
  sed -i "0,/^## /s//${HEADING}\n\n### 变更\n\n- \n\n## /" CHANGELOG.md
  echo "CHANGELOG 已插入 ${HEADING}"
fi

# ─── 提交 + 打 tag ────────────────────────────────────
git add pubspec.yaml CHANGELOG.md
git commit -m "release: ${TAG_VERSION}"

git tag "${TAG_VERSION}"
echo "已创建 tag: ${TAG_VERSION}"

# ─── 推送 ─────────────────────────────────────────────
git push origin main
git push origin "${TAG_VERSION}"

echo ""
echo "✅ ${TAG_VERSION} 已推送"
echo "⏳ 等待 CI 构建完成后运行:"
echo "   gh run watch --repo kitsuneMori96/EcjtuAuth"
echo ""
echo "构建完成后创建 release:"
echo "   ./scripts/publish-release.sh ${TAG_VERSION}"
