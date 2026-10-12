#!/bin/bash
# Package the Swift app with the same libmpv/FFmpeg runtime used by Kazumi.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_MEDIA="${MPV_FRAMEWORKS_DIR:-/Applications/Kazumi.app/Contents/Frameworks}"
TASK_APP="${1:-$TASK_ROOT/build/XiaoLizi.app}"
TASK_DERIVED="$TASK_ROOT/.build/packaging"
if [[ ! -f "$TASK_MEDIA/Mpv.framework/Mpv" ]]; then
    echo "Missing Kazumi media frameworks. Set MPV_FRAMEWORKS_DIR to their Frameworks directory." >&2
    exit 1
fi
xcodebuild -project "$TASK_ROOT/XiaoLizi.xcodeproj" -scheme XiaoLizi \
    -destination 'platform=macOS' -configuration Release -derivedDataPath "$TASK_DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p "$(dirname "$TASK_APP")"
ditto "$TASK_DERIVED/Build/Products/Release/XiaoLizi.app" "$TASK_APP"
mkdir -p "$TASK_APP/Contents/Frameworks"
for name in Mpv Ass Avcodec Avfilter Avformat Avutil Swresample Swscale Uchardet Freetype Fribidi Harfbuzz Png16 Dav1d Mbedcrypto Mbedtls Mbedx509 Xml2; do
    if [[ -d "$TASK_MEDIA/$name.framework" ]]; then
        ditto "$TASK_MEDIA/$name.framework" "$TASK_APP/Contents/Frameworks/$name.framework"
    fi
done
cp "$TASK_ROOT/LICENSE" "$TASK_APP/Contents/Resources/LICENSE-GPL-3.0.txt"
codesign --force --deep --sign - "$TASK_APP"
echo "$TASK_APP"
