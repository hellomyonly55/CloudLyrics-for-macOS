# Security Policy

## Supported versions

CloudLyrics is currently an experimental pre-release. Security fixes are applied to the latest release only.

## Reporting a vulnerability

Please report suspected vulnerabilities privately through the repository's GitHub Security Advisory page instead of opening a public issue. Include the affected version, macOS version, reproduction steps, and the expected impact.

Do not include credentials, personal listening data, or other sensitive information in a report. Please allow a reasonable period for investigation before public disclosure.

## Security boundaries

CloudLyrics connects to a NetEase CEF debugging endpoint restricted to `127.0.0.1:9222`. Other processes running under the same Mac may still be able to reach local ports. CloudLyrics also sends track metadata to NetEase endpoints or LRCLIB to retrieve lyrics. See the README for details.
