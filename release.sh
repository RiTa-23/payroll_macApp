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
#   3. リリース用DMG作成（create-dmg: Applicationsドロップリンク付き）
#   4. タグ作成 & push
#   5. GitHub Release作成（DMG添付・リリースノート自動生成）
#
# 要件: brew install create-dmg gh
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
DMG_PATH="build/${APP_NAME}-${VERSION}.dmg"

echo "🔖 リリースバージョン: ${VERSION}（タグ: ${TAG}）"

# ---- 前提チェック ----
if ! command -v gh >/dev/null; then
  echo "❌ gh CLIがインストールされていません: brew install gh && gh auth login" >&2
  exit 1
fi
if ! command -v create-dmg >/dev/null; then
  echo "❌ create-dmgがインストールされていません: brew install create-dmg" >&2
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

# ---- 3. DMG作成（Applicationsへのドロップリンク付き） ----
echo "💿 リリース用DMG作成: ${DMG_PATH}"
rm -f "$DMG_PATH"
# .appのみをDMGに入れるためステージングディレクトリに隔離
STAGING="build/dmg_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "build/${APP_NAME}.app" "$STAGING/"
# create-dmgは初回マウントに失敗することがあるため3回までリトライ
for attempt in 1 2 3; do
  if create-dmg \
      --volname "${APP_NAME}" \
      --window-pos 200 120 \
      --window-size 560 360 \
      --icon-size 110 \
      --text-size 12 \
      --icon "${APP_NAME}.app" 150 190 \
      --app-drop-link 410 190 \
      --hide-extension "${APP_NAME}.app" \
      "$DMG_PATH" \
      "$STAGING/"; then
    break
  fi
  echo "   ⚠️  create-dmg 試行 ${attempt} 失敗、リトライ..."
  rm -f "$DMG_PATH"
  if [ "$attempt" -eq 3 ]; then
    echo "❌ DMG作成に失敗しました" >&2
    exit 1
  fi
done
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "   SHA-256: ${SHA256}"

# ---- 4. タグ作成 & push ----
echo "🏷  タグ ${TAG} を作成してpush..."
git tag "$TAG"
git push origin HEAD "$TAG"

# ---- 5. GitHub Release作成 ----
echo "🚀 GitHub Releaseを作成..."
NOTES=$(cat <<EOF
## インストール

1. 下の **${APP_NAME}-${VERSION}.dmg** をダウンロードして開く
2. 表示されたウィンドウで \`PayrollCalculator.app\` を **Applications** フォルダにドラッグ
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
gh release create "$TAG" "$DMG_PATH" \
  --title "${APP_NAME} ${VERSION}" \
  --notes "$NOTES" \
  --generate-notes

echo ""
echo "✅ リリース完了:"
gh release view "$TAG" --json url -q .url
