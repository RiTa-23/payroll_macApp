#!/bin/bash
# GitHub Releases への公開を1コマンドで行うスクリプト
#
# 使い方:
#   ./release.sh            # Info.plistのバージョンでリリース
#   ./release.sh 1.1.0      # バージョンを指定してリリース（Info.plistも更新）
#
# 処理内容:
#   1. Info.plistのバージョン同期
#   2. クリーンビルド（build.sh）
#   3. リリース用zip作成（dittoで.appを正しくアーカイブ）
#   4. タグ作成 & push
#   5. GitHub Release作成（zip添付・リリースノート自動生成）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PayrollCalculator"
PLIST="Info.plist"
current_in_plist() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null; }

# ---- バージョン確定 ----
if [ $# -ge 1 ]; then
  VERSION="$1"
else
  VERSION="$(current_in_plist)"
fi
TAG="v${VERSION}"
ZIP_PATH="build/${APP_NAME}-${VERSION}.zip"

echo "🔖 リリースバージョン: ${VERSION}（タグ: ${TAG}）"

# ---- 前提チェック ----
if ! command -v gh >/dev/null; then
  echo "❌ gh CLIがインストールされていません: brew install gh && gh auth login" >&2
  exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "❌ タグ ${TAG} は既に存在します" >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ コミットされていない変更があります。先にコミットしてください:" >&2
  git status --short
  exit 1
fi

# ---- 1. Info.plist のバージョン同期 ----
if [ "$(current_in_plist)" != "$VERSION" ]; then
  echo "📝 Info.plistのバージョンを ${VERSION} に更新"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$PLIST"
  git add "$PLIST"
  git commit -m "chore: バージョンを ${VERSION} に更新"
fi

# ---- 2. ビルド ----
echo "🛠  ビルド..."
./build.sh

# ---- 3. zip作成（dittoはsymlink・権限・拡張属性を正しく保持する） ----
echo "📦 リリース用zip作成: ${ZIP_PATH}"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "build/${APP_NAME}.app" "$ZIP_PATH"
SHA256=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
echo "   SHA-256: ${SHA256}"

# ---- 4. タグ作成 & push ----
echo "🏷  タグ ${TAG} を作成してpush..."
git tag "$TAG"
git push origin HEAD "$TAG"

# ---- 5. GitHub Release作成 ----
echo "🚀 GitHub Releaseを作成..."
NOTES=$(cat <<EOF
## インストール

1. 下の **${APP_NAME}-${VERSION}.zip** をダウンロードして展開
2. \`PayrollCalculator.app\` を **アプリケーション** フォルダに移動
3. 初回起動は **右クリック → 「開く」→「開く」** を選択
   （未公証アプリのため、通常のダブルクリックでは警告が出ます）
4. カレンダーへのアクセスを求められたら「許可」

## 動作環境

- macOS 14 Sonoma 以降（Apple Silicon / arm64）

## チェックサム

\`\`\`
${SHA256}
\`\`\`
EOF
)
gh release create "$TAG" "$ZIP_PATH" \
  --title "${APP_NAME} ${VERSION}" \
  --notes "$NOTES" \
  --generate-notes

echo ""
echo "✅ リリース完了:"
gh release view "$TAG" --json url -q .url
