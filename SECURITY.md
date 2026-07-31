# Security Policy

## Supported versions

CloudLyrics is currently an experimental pre-release. Security fixes are applied to the latest release only.

## Reporting a vulnerability

Please report suspected vulnerabilities privately through the repository's GitHub Security Advisory page instead of opening a public issue. Include the affected version, macOS version, reproduction steps, and the expected impact.

Do not include credentials, personal listening data, or other sensitive information in a report. Please allow a reasonable period for investigation before public disclosure.

## Security boundaries

CloudLyrics does not expose a CEF debugging endpoint or inject code into a player. For NetEase 3.1.8, it read-only decodes the app's local `lastPlaying` state and reads metadata from its local play queue; it does not modify or lock those files. NetEase playback commands use MediaRemote when available or invoke only its previous/play-pause/next menu items through Accessibility. For KuGou tracks, CloudLyrics reads lyrics from `~/Library/Containers/com.kugou.mac.Music/Data/Documents/Caches/kgLyric` without modifying that directory. Because KuGou 3.3.2 does not continuously publish metadata through MediaRemote, Accessibility is also used to read its playback-bar text and invoke its playback menu items. Dual-player selection reads CoreAudio's per-process `isRunningOutput` Boolean; it does not capture, record, or analyze audio. When local lyrics are unavailable, track metadata may be sent to NetEase endpoints or LRCLIB. See the README for details.
