#!/bin/bash
# Build SmartCapture and package it as a background-agent .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SmartCapture"
BUILD_CONFIG="release"
APP_BUNDLE="${APP_NAME}.app"

echo "Building (${BUILD_CONFIG})..."
swift build -c "${BUILD_CONFIG}"

BIN_PATH="$(swift build -c "${BUILD_CONFIG}" --show-bin-path)/${APP_NAME}"

echo "Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Code signing. Prefers a stable self-signed identity so the Screen Recording
# permission survives rebuilds; falls back to ad-hoc ("-") if none is present.
# Override with:  SIGN_IDENTITY="Your Cert Name" ./build_app.sh
STABLE_IDENTITY="SmartCapture Self-Signed"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    if security find-identity -p codesigning 2>/dev/null | grep -q "${STABLE_IDENTITY}"; then
        SIGN_IDENTITY="${STABLE_IDENTITY}"
    else
        SIGN_IDENTITY="-"
    fi
fi
if [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "Signing (ad-hoc; permission may reset on rebuild)..."
else
    echo "Signing with identity: ${SIGN_IDENTITY}"
fi
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

echo "Done: $(pwd)/${APP_BUNDLE}"
echo "Run:  open \"${APP_BUNDLE}\""
echo "Note: grant Screen Recording permission on first launch for capture to work."
