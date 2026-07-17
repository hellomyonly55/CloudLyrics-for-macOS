# Security Policy

## Supported versions

CloudLyrics is currently an experimental pre-release. Security fixes are applied to the latest release only.

## Reporting a vulnerability

Please report suspected vulnerabilities privately through the repository's GitHub Security Advisory page instead of opening a public issue. Include the affected version, macOS version, reproduction steps, and the expected impact.

Do not include credentials, personal listening data, or other sensitive information in a report. Please allow a reasonable period for investigation before public disclosure.

## Security boundaries

CloudLyrics connects to a NetEase CEF debugging endpoint restricted to `127.0.0.1:9222`. Other processes running under the same Mac may still be able to reach local ports. For KuGou tracks it reads lyrics from `~/Library/Containers/com.kugou.mac.Music/Data/Documents/Caches/kgLyric` without modifying that directory. It dynamically probes the local MediaRemote framework and, because KuGou 3.3.2 does not continuously publish metadata there, uses Accessibility permission to read KuGou's playback-bar text and invoke only its previous/play-pause/next menu items. Dual-player selection reads CoreAudio's per-process `isRunningOutput` Boolean; it does not capture, record, or analyze audio. When local lyrics are unavailable, track metadata may be sent to NetEase endpoints or LRCLIB. See the README for details.
