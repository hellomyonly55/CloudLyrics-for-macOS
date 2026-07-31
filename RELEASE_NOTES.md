# CloudLyrics v0.2.2

CloudLyrics v0.2.2 adds reliable no-argument synchronization for NetEase Cloud Music 3.1.8 and fixes lyric lines briefly jumping backward during normal playback.

## Highlights

- NetEase 3.1.8 works when launched normally, without debugging arguments or an automatic restart
- Read-only decoding of NetEase's local `lastPlaying` state for track identity, duration, and native progress
- Monotonic interpolation that rejects stale LevelDB records and delayed writes across lyric boundaries
- CoreAudio-aware pause handling that freezes progress instead of rewinding to an older on-disk value
- Original menu-bar push/fade lyric animation retained from v0.2.1
- Removed CEF WebSocket polling, webpack scans, renderer injection, and the local debugging endpoint
- Universal app for Apple Silicon and Intel Macs

## Compatibility and security notes

- Requires macOS 14 or later and is tested with NetEase Cloud Music 3.1.8 and KuGou Music 3.3.2.
- Playback synchronization relies on player-local data formats, Accessibility, CoreAudio, and MediaRemote, and may require updates after player or macOS changes.
- NetEase Cloud Music requires no debugging arguments and is never restarted by CloudLyrics; synchronization prefers its read-only local `lastPlaying` state and uses System Now Playing as a compatibility fallback.
- KuGou lyrics are read from its local lyric cache when available; otherwise track metadata may be sent to NetEase endpoints or LRCLIB.
- This build is ad-hoc signed and not notarized by Apple. On first launch, Control-click the app and choose Open, or approve it in System Settings → Privacy & Security. Do not disable Gatekeeper globally.

This is an unofficial project and is not affiliated with NetEase, KuGou, or LRCLIB.
