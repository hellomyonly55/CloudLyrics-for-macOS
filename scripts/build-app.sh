#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${CLOUDLYRICS_APP_PATH:-/Applications/CloudLyrics.app}"
CONTENTS="$APP/Contents"

cd "$ROOT"
swift build -c release
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"
cp "$ROOT/.build/release/CloudLyrics" "$CONTENTS/MacOS/CloudLyrics"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
chmod +x "$CONTENTS/MacOS/CloudLyrics"
codesign --force --deep --sign - --identifier io.github.hellomyonly55.CloudLyrics "$APP"

echo "$APP"
