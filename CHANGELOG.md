# Changelog

All notable changes to CloudLyrics are documented in this file.

## Unreleased

## [0.2.2] - 2026-08-01

### Fixed

- Prevented delayed NetEase progress writes and transient playback-state changes from pulling interpolated playback backward across lyric boundaries, and clamped interpolation at the track end until NetEase reports the next track or repeat.
- Ignored one-off stale backward `lastPlaying` records exposed by LevelDB compaction, while still accepting confirmed seeks, same-track repeats, and paused seeks.

### Changed

- Replaced NetEase CEF/webpack injection with System Now Playing plus read-only decoding of NetEase's exact local `lastPlaying` progress, so NetEase no longer requires debugging arguments or an automatic restart and manual seeks are re-synchronized on the next native update.

### Performance

- Removed NetEase WebSocket polling and webpack module scans. The local fallback checks LevelDB file metadata at most twice per second, reads only a bounded log tail when it changes, caches track metadata, and interpolates solely between exact native progress observations.

### Security

- Removed the local NetEase debugging endpoint and renderer-process JavaScript injection.

## [0.2.1] - 2026-07-18

### Fixed

- Retained the last valid KuGou playback snapshot when comments or image overlays temporarily hide the playback bar.
- Prioritized the persistent KuGou playback controls during Accessibility discovery.

### Performance

- Cached KuGou playback Accessibility nodes and moved fallback discovery to a serialized background queue.
- Replaced unconditional menu-bar redraws with coalesced state-driven updates and adaptive player polling.
- Cached CoreAudio activity, tracked player processes through workspace notifications, and reduced redundant MediaRemote requests.
- Indexed the local KuGou lyrics directory and invalidated it when directory contents change.
- Reduced measured KuGou playback CPU usage from approximately 5.5% to 0.835% over a 60-second sample.

## [0.2.0] - 2026-07-17

### Added

- KuGou Music 3.3.2 playback synchronization and controls through MediaRemote when available, with a tested macOS Accessibility fallback.
- Local KuGou KRC/LRC parsing, including translated lines, with NetEase and LRCLIB fallback.
- Automatic selection of the active NetEase or KuGou player and player-scoped lyric caching.
- CoreAudio process-output detection so a background player takes precedence over an idle foreground player.
- KuGou whole-second progress interpolation and a calibrated 0.5-second lyric lead.

### Changed

- CloudLyrics now waits for the user to start a player instead of launching NetEase automatically.
- Source builds now install to `/Applications/CloudLyrics.app` by default.

## [0.1.0] - 2026-07-13

### Added

- Menu-bar lyrics display with single-line, next-line, and translation modes.
- Playback controls, appearance settings, local cache, and launch-at-login support.
- NetEase lyrics provider with LRCLIB fallback.
- Universal macOS release packaging for Apple Silicon and Intel Macs.
- Homebrew Cask definition through `hellomyonly55/homebrew-tap`.

### Security

- Restricted the local CEF debugging endpoint to `127.0.0.1:9222`.
- Validated debugger WebSocket URLs before connecting.
- Removed unused Apple private-framework and Accessibility code.
