# Changelog

All notable changes to CloudLyrics are documented in this file.

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
