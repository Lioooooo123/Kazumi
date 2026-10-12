#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild was not found. Install Xcode 16 or newer and run this script on macOS." >&2
  exit 1
fi

xcodebuild \
  -project XiaoLizi.xcodeproj \
  -scheme XiaoLizi \
  -destination 'platform=macOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
