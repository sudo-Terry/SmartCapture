#!/bin/bash
# SmartCapture 을 빌드해 백그라운드 에이전트용 .app 번들로 묶는다.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SmartCapture"
BUILD_CONFIG="release"
APP_BUNDLE="${APP_NAME}.app"

echo "▶︎ Swift 빌드 (${BUILD_CONFIG})..."
swift build -c "${BUILD_CONFIG}"

BIN_PATH="$(swift build -c "${BUILD_CONFIG}" --show-bin-path)/${APP_NAME}"

echo "▶︎ .app 번들 구성..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# 코드서명. 기본은 ad-hoc("-").
# 자체 서명/Developer ID 인증서가 있으면:  SIGN_IDENTITY="SmartCapture Dev" ./build_app.sh
# 안정적 인증서로 서명하면 재빌드해도 화면 기록 권한이 유지됩니다.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "▶︎ ad-hoc 코드서명 (재빌드 시 권한 초기화될 수 있음)..."
else
    echo "▶︎ 코드서명: ${SIGN_IDENTITY}"
fi
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

echo "✅ 완료: $(pwd)/${APP_BUNDLE}"
echo "   실행:   open \"${APP_BUNDLE}\""
echo "   ※ 최초 실행 시 '화면 기록' 권한을 허용해야 캡처가 동작합니다."
