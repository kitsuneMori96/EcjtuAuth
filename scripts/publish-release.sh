#!/usr/bin/env bash
# 把 Build workflow 产出的 Windows/Android 产物发布为 GitHub Release。
#
# 用法:
#   scripts/publish-release.sh <version>            例如: 1.3.0
#   scripts/publish-release.sh --dry-run <version>  只打印计划，不改远端
#
# release 正文**不手写**：从 CHANGELOG.md 中抽取 `## <version>` 章节。
# 抽不到直接失败，避免把旧版本内容或整个 CHANGELOG 发上去。
set -euo pipefail

REPO="kitsuneMori96/EcjtuAuth"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DRY_RUN=0
VERSION=""

usage() {
  cat <<'EOF'
用法: publish-release.sh [--dry-run] <version>

  <version>    与 tag / CHANGELOG 章节一致，例如 1.3.0
  --dry-run    只解析 Build 运行与 release notes，不下载产物、不删除/创建 release
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "❌ 未知参数: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -n "$VERSION" ]]; then
        echo "❌ 只能指定一个版本号（已有 ${VERSION}）" >&2
        exit 2
      fi
      VERSION="$1"
      ;;
  esac
  shift
done

if [[ -z "$VERSION" ]]; then
  usage >&2
  exit 2
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ $DRY_RUN -eq 1 ]]; then
  echo "🔎 DRY RUN：不会下载产物，也不会修改远端 release"
fi
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

# ─── 提取当前版本的 CHANGELOG 章节 ────────────────────
NOTES_FILE="${WORK_DIR}/notes.md"
extract_notes() {
  local version="$1"
  awk -v ver="$version" '
    /^## / {
      if (in_section) exit
      # 只认 `## <version>` 或 `## <version> - 日期`，避免 1.3 命中 1.30
      if ($2 == ver) in_section = 1
    }
    in_section { print }
  ' "${REPO_DIR}/CHANGELOG.md"
}

extract_notes "$VERSION" > "$NOTES_FILE"

if [[ ! -s "$NOTES_FILE" ]]; then
  echo "❌ CHANGELOG.md 中找不到 ${VERSION} 章节（需以 '## ${VERSION}' 开头）" >&2
  exit 1
fi

echo "📋 release notes（来自 CHANGELOG.md，共 $(wc -l < "$NOTES_FILE" | tr -d ' ') 行）:"
echo "────────────────────────────────────────"
cat "$NOTES_FILE"
echo "────────────────────────────────────────"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "🔎 DRY RUN：将执行以下操作"
  if gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    echo "   - 删除已存在的 release ${VERSION}"
  fi
  echo "   - gh run download ${RUN_ID} --repo ${REPO}"
  echo "   - gh release create ${VERSION} --title v${VERSION} --prerelease --notes-file <CHANGELOG 章节>"
  echo "✅ DRY RUN 结束（未改动远端）"
  exit 0
fi

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
  --notes-file "$NOTES_FILE"
  "$WIN_ZIP"
)

if [[ -n "$APK" ]]; then
  ARGS+=("$APK")
fi

gh release create "$VERSION" "${ARGS[@]}"

echo ""
echo "✅ v${VERSION} 已发布"
echo "🔗 https://github.com/${REPO}/releases/tag/v${VERSION}"
