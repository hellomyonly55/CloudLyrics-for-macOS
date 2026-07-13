#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${1:-0.1.0}"
IDENTIFIER="io.github.hellomyonly55.CloudLyrics"
OUTPUT_DIR="$ROOT/.build/releases"
STAGING_DIR="${TMPDIR%/}/CloudLyrics-release/$VERSION-$(date +%Y%m%d%H%M%S)-$$"
APP="$STAGING_DIR/CloudLyrics.app"
CONTENTS="$APP/Contents"
ZIP="$OUTPUT_DIR/CloudLyrics-v$VERSION-universal.zip"
CHECKSUM="$ZIP.sha256"

if [[ "$VERSION" != <->.<->.<-> ]]; then
    print -u2 "Version must use semantic versioning, for example 0.1.0"
    exit 2
fi

PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"
if [[ "$PLIST_VERSION" != "$VERSION" ]]; then
    print -u2 "Info.plist version $PLIST_VERSION does not match requested release $VERSION"
    exit 4
fi

if [[ -e "$ZIP" || -e "$CHECKSUM" ]]; then
    print -u2 "Release output already exists: $ZIP"
    print -u2 "Remove the two explicit output files manually before rebuilding this version."
    exit 3
fi

cd "$ROOT"
ARM_SCRATCH="$ROOT/.build/release-arm64"
INTEL_SCRATCH="$ROOT/.build/release-x86_64"
swift build -c release --arch arm64 --scratch-path "$ARM_SCRATCH"
swift build -c release --arch x86_64 --scratch-path "$INTEL_SCRATCH"
ARM_BIN_DIR="$(swift build -c release --arch arm64 --scratch-path "$ARM_SCRATCH" --show-bin-path)"
INTEL_BIN_DIR="$(swift build -c release --arch x86_64 --scratch-path "$INTEL_SCRATCH" --show-bin-path)"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$OUTPUT_DIR"
lipo -create "$ARM_BIN_DIR/CloudLyrics" "$INTEL_BIN_DIR/CloudLyrics" -output "$CONTENTS/MacOS/CloudLyrics"
COPYFILE_DISABLE=1 cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
COPYFILE_DISABLE=1 cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
chmod +x "$CONTENTS/MacOS/CloudLyrics"
codesign --force --deep --sign - --identifier "$IDENTIFIER" "$APP"

COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc "$APP" "$ZIP"
(cd "$OUTPUT_DIR" && shasum -a 256 "$ZIP:t") > "$CHECKSUM"

print "$ZIP"
print "$CHECKSUM"
