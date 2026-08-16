#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PayrollCalculator"
APP_DIR="build/${APP_NAME}.app"

mkdir -p build

echo "🛠  Compiling Swift sources..."
swiftc -O -swift-version 5 -o "build/${APP_NAME}" Sources/*.swift

echo "📦 Assembling ${APP_NAME}.app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "build/${APP_NAME}" "${APP_DIR}/Contents/MacOS/"
cp Info.plist "${APP_DIR}/Contents/"
if [ -f ".assets/AppIcon.icns" ]; then
    cp ".assets/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

echo "🖋  Ad-hoc code signing..."
codesign --force --sign - "${APP_DIR}"

echo "✅ Done: $(pwd)/${APP_DIR}"
echo "   起動: open ${APP_DIR}"
