#!/usr/bin/env bash
# 生成 Android 发布签名 keystore，并打印 CI 需要的 Secrets。
#
# 用法（在仓库根目录执行）：
#   ./scripts/generate-android-keystore.sh [keyAlias]
#
# 默认输出：android/app/release-key.jks
# 生成后在 android/key.properties 写入配置（该文件已被 .gitignore 忽略）。
#
# 需要配置到 GitHub Actions 的 Secrets：
#   ANDROID_KEYSTORE_BASE64    keystore 文件的 base64（单行）
#   ANDROID_KEYSTORE_PASSWORD  storePassword
#   ANDROID_KEY_ALIAS          keyAlias
#   ANDROID_KEY_PASSWORD       keyPassword
set -euo pipefail

cd "$(dirname "$0")/.."

ALIAS="${1:-ecjtuauth}"
KEYSTORE="android/app/release-key.jks"
KEY_PROPERTIES="android/key.properties"

if [[ -e "$KEYSTORE" ]]; then
  echo "错误: $KEYSTORE 已存在，请先备份/删除后再生成" >&2
  exit 1
fi

read -r -p "证书主体 CN（默认 EcjtuAuth）: " CN
CN="${CN:-EcjtuAuth}"
read -r -p "组织 O（默认 EcjtuAuth）: " ORG
ORG="${ORG:-EcjtuAuth}"
read -r -s -p "storePassword（keystore 密码）: " STORE_PASS; echo
read -r -s -p "keyPassword（留空则与 storePassword 相同）: " KEY_PASS; echo
KEY_PASS="${KEY_PASS:-$STORE_PASS}"

keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$STORE_PASS" \
  -keypass "$KEY_PASS" \
  -dname "CN=$CN, OU=Mobile, O=$ORG, L=Nanchang, ST=Jiangxi, C=CN"

cat > "$KEY_PROPERTIES" <<EOF
storeFile=release-key.jks
storePassword=$STORE_PASS
keyAlias=$ALIAS
keyPassword=$KEY_PASS
EOF

echo
echo "已生成: $KEYSTORE"
echo "已写入: $KEY_PROPERTIES（已 gitignore，不要提交）"
echo
echo "设置 GitHub Secrets（示例）："
echo "  base64 -w0 $KEYSTORE | gh secret set ANDROID_KEYSTORE_BASE64 --repo <owner>/<repo>"
echo "  gh secret set ANDROID_KEYSTORE_PASSWORD --repo <owner>/<repo>   # 值: <storePassword>"
echo "  gh secret set ANDROID_KEY_ALIAS --repo <owner>/<repo>          # 值: $ALIAS"
echo "  gh secret set ANDROID_KEY_PASSWORD --repo <owner>/<repo>       # 值: <keyPassword>"
echo
echo "注意: keystore 请离线备份；丢失后无法覆盖升级已发布的应用。"
