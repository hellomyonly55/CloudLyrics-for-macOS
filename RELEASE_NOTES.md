# CloudLyrics v0.2.1

CloudLyrics v0.2.1 is the first stable release, focused on KuGou compatibility and substantially lower background CPU and energy use.

## Highlights

- KuGou and NetEase playback synchronization with automatic active-player selection
- Local KuGou KRC/LRC support with NetEase and LRCLIB fallback
- Cached KuGou Accessibility playback nodes with automatic compatibility fallback
- State-driven menu-bar updates and adaptive player monitoring
- Universal app for Apple Silicon and Intel Macs
- Measured KuGou playback CPU reduction from approximately 5.5% to 0.835%

## Compatibility and security notes

- Requires macOS 14 or later and is tested with NetEase Cloud Music 3.1.7 and KuGou Music 3.3.2.
- Playback synchronization relies on internal player behavior, Accessibility, and MediaRemote, and may require updates after player or macOS changes.
- CloudLyrics may gracefully quit and relaunch NetEase Cloud Music with a local debugging endpoint restricted to `127.0.0.1:9222`.
- KuGou lyrics are read from its local lyric cache when available; otherwise track metadata may be sent to NetEase endpoints or LRCLIB.
- This build is ad-hoc signed and not notarized by Apple. On first launch, Control-click the app and choose Open, or approve it in System Settings → Privacy & Security. Do not disable Gatekeeper globally.

This is an unofficial project and is not affiliated with NetEase, KuGou, or LRCLIB.
