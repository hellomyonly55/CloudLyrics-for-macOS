# CloudLyrics v0.1.0

First experimental pre-release of CloudLyrics, a menu-bar lyrics app for NetEase Cloud Music on macOS.

## Highlights

- Current, next-line, and translated lyrics display modes
- Playback controls and configurable appearance
- NetEase lyrics with LRCLIB fallback
- Universal app for Apple Silicon and Intel Macs

## Compatibility and security notes

- Requires macOS 14 or later and is currently tested with NetEase Cloud Music 3.1.7.
- Playback synchronization relies on internal NetEase client behavior and may break after client updates.
- CloudLyrics may gracefully quit and relaunch NetEase Cloud Music with a local debugging endpoint restricted to `127.0.0.1:9222`.
- Track metadata is sent to NetEase endpoints or LRCLIB to retrieve lyrics.
- This build is ad-hoc signed and not notarized by Apple. On first launch, Control-click the app and choose Open, or approve it in System Settings → Privacy & Security. Do not disable Gatekeeper globally.

This is an unofficial project and is not affiliated with NetEase or LRCLIB.
