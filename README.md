# CloudLyrics

[English](#english) · [中文](#中文)

## 中文

CloudLyrics 是一款为 macOS 网易云音乐设计的菜单栏双行歌词工具。它可以显示当前歌词、下一行歌词或翻译，并提供基础播放控制。

> [!WARNING]
> 这是实验性、非官方项目，与网易云音乐、网易公司及 LRCLIB 均无隶属、认可或合作关系。播放器同步依赖网易云音乐 3.1.7 的内部 CEF/webpack 实现，客户端更新后可能失效。

### 功能

- 菜单栏歌词窗口，支持单行、下一行和翻译模式
- 字体、颜色、描边、阴影和位置设置
- 上一首、播放/暂停、下一首控制
- 网易云歌词与 LRCLIB 回退
- 本地歌词缓存和登录时启动选项
- 支持 Apple Silicon 与 Intel Mac

### 系统要求

- macOS 14 Sonoma 或更高版本
- 网易云音乐 macOS 客户端 3.1.7，安装在 `/Applications/NeteaseMusic.app`
- 源码构建需要 Xcode/Swift 6

### 安装

#### GitHub Release

从 [Releases](https://github.com/hellomyonly55/CloudLyrics-for-MacOS/releases) 下载 `CloudLyrics-v0.1.0-universal.zip`，解压后将 `CloudLyrics.app` 移入“应用程序”。

当前应用使用 ad-hoc 签名且未经 Apple 公证。首次启动时请在 Finder 中右键应用并选择“打开”；如果仍被拦截，请前往“系统设置 → 隐私与安全”确认打开。请勿为了安装而全局关闭 Gatekeeper。

#### Homebrew

主仓库与 `hellomyonly55/homebrew-tap` 公开后，可运行：

```bash
brew install --cask hellomyonly55/tap/cloudlyrics-for-macos
```

在两个仓库仍为 Private 时，普通用户无法通过 Homebrew 下载私有 Release 附件。

#### 从源码构建

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open ~/Applications/CloudLyrics.app
```

菜单栏状态项需要完整的 macOS 应用包，请不要将 `swift run CloudLyrics` 作为日常启动方式。

### 使用与卸载

CloudLyrics 会自动启动网易云音乐。若网易云已经以普通方式运行，CloudLyrics 会先正常退出它，再以仅绑定至 `127.0.0.1:9222` 的本地 CEF 调试模式重启。用户主动退出网易云后不会被立即循环拉起。

卸载时退出 CloudLyrics 并将 `/Applications/CloudLyrics.app`（或 `~/Applications/CloudLyrics.app`）移到废纸篓。缓存位于 `~/Library/Caches/CloudLyrics`，设置位于 `~/Library/Preferences/io.github.hellomyonly55.CloudLyrics.plist`；如需彻底清理，请分别手动删除这些明确路径。

### 隐私与安全

- CloudLyrics 不包含遥测或账号系统。
- 为查找歌词，当前歌曲 ID、标题、歌手及可能的时长会发送至网易云音乐接口或 LRCLIB。
- 歌词缓存在当前用户的 `~/Library/Caches/CloudLyrics/lyrics.json`。
- 本地 CEF 调试接口仅绑定 `127.0.0.1:9222`，但同一台 Mac 上的其他本地进程仍可能访问该端口。不要在不可信的多用户环境中运行。
- 网易云歌词接口和客户端内部结构均不是稳定的公开 API。

安全问题请参阅 [SECURITY.md](SECURITY.md)。

### 测试与发布构建

```bash
swift test
./scripts/package-release.sh 0.1.0
```

发布脚本会在 `.build/releases/` 中生成 Universal ZIP 和 SHA-256 文件。

### 已知限制

- 目前仅针对网易云音乐 3.1.7 验证。
- 固定使用本地端口 9222；如果端口被占用，播放器同步会失败。
- 未经 Apple 公证，首次启动需要用户确认。
- 非公开网易云歌词接口失效时会回退到 LRCLIB，但不保证所有歌曲都有同步歌词。

## English

CloudLyrics is an experimental macOS menu-bar lyrics app for NetEase Cloud Music. It displays the current line together with the next line or translation and provides basic playback controls.

> [!WARNING]
> This is an unofficial project and is not affiliated with, endorsed by, or sponsored by NetEase Cloud Music, NetEase, or LRCLIB. Playback synchronization relies on internal CEF/webpack behavior observed in NetEase Cloud Music 3.1.7 and may break after client updates.

### Features

- Menu-bar lyrics window with single-line, next-line, and translation modes
- Configurable font, colors, outline, shadow, and position
- Previous, play/pause, and next controls
- NetEase lyrics with LRCLIB fallback
- Local lyrics cache and launch-at-login option
- Universal support for Apple Silicon and Intel Macs

### Requirements

- macOS 14 Sonoma or later
- NetEase Cloud Music for macOS 3.1.7 at `/Applications/NeteaseMusic.app`
- Xcode/Swift 6 for source builds

### Installation

#### GitHub Release

Download `CloudLyrics-v0.1.0-universal.zip` from [Releases](https://github.com/hellomyonly55/CloudLyrics-for-MacOS/releases), unzip it, and move `CloudLyrics.app` to Applications.

The current build is ad-hoc signed and not notarized by Apple. On first launch, Control-click the app in Finder and choose Open. If macOS still blocks it, approve it in System Settings → Privacy & Security. Do not disable Gatekeeper globally.

#### Homebrew

After both the main repository and `hellomyonly55/homebrew-tap` become public, install with:

```bash
brew install --cask hellomyonly55/tap/cloudlyrics-for-macos
```

Regular Homebrew users cannot download private GitHub Release assets while the repositories remain private.

#### Build from source

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open ~/Applications/CloudLyrics.app
```

Use the full app bundle for daily use; `swift run CloudLyrics` does not provide the intended menu-bar app environment.

### Behavior and removal

CloudLyrics starts NetEase Cloud Music automatically. If NetEase is already running normally, CloudLyrics terminates it gracefully and relaunches it with a local CEF debugging endpoint bound to `127.0.0.1:9222`. It does not immediately relaunch NetEase after the user intentionally quits it.

To uninstall, quit CloudLyrics and move `/Applications/CloudLyrics.app` (or `~/Applications/CloudLyrics.app`) to Trash. Cache data is stored at `~/Library/Caches/CloudLyrics`, and preferences are stored at `~/Library/Preferences/io.github.hellomyonly55.CloudLyrics.plist`; remove these exact paths manually only if you want a full cleanup.

### Privacy and security

- CloudLyrics contains no telemetry or account system.
- To find lyrics, the current track ID, title, artist, and possibly duration are sent to NetEase endpoints or LRCLIB.
- Lyrics are cached locally in `~/Library/Caches/CloudLyrics/lyrics.json`.
- The CEF debugging endpoint is restricted to `127.0.0.1:9222`, but other local processes on the same Mac may still access that port. Avoid running it in an untrusted multi-user environment.
- NetEase lyrics endpoints and client internals are not stable public APIs.

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

### Tests and release build

```bash
swift test
./scripts/package-release.sh 0.1.0
```

The release script writes the Universal ZIP and its SHA-256 file under `.build/releases/`.

### Known limitations

- Only NetEase Cloud Music 3.1.7 has been verified.
- Port 9222 is fixed; synchronization fails if another process occupies it.
- The app is not notarized and requires user approval on first launch.
- LRCLIB fallback cannot guarantee synchronized lyrics for every track.

## License

[MIT](LICENSE)
