#!/usr/bin/env bash
# Build Satchel in Release, re-sign it, and replace ~/Applications/Satchel.app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-/tmp/satchel-build}"
APP_NAME="Satchel"
DEST="${HOME}/Applications/${APP_NAME}.app"

cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate

xcodebuild \
  -project Satchel.xcodeproj \
  -scheme Satchel \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP="$(find "$DERIVED_DATA/Build/Products/Release" -name "${APP_NAME}.app" -type d | head -1)"
if [[ -z "${APP}" || ! -d "${APP}" ]]; then
  echo "Build did not produce ${APP_NAME}.app" >&2
  exit 1
fi

# First "Apple Development" identity. The hash is detected at runtime and never stored in the repo.
HASH="$(security find-identity -v -p codesigning | sed -n 's/^[[:space:]]*[0-9][0-9]*) \([0-9A-F][0-9A-F]*\) "Apple Development:.*/\1/p' | head -1 || true)"
if [[ -n "${HASH}" ]]; then
  SIGN_ID="$HASH"
else
  SIGN_ID="-"
  echo "No Apple Development identity found; signing ad-hoc." >&2
fi

codesign --force --deep --options runtime --sign "$SIGN_ID" \
  --entitlements "$ROOT/Satchel/Satchel.entitlements" \
  "$APP"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  pkill -x "$APP_NAME" || true
  sleep 0.4
fi

mkdir -p "${HOME}/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
