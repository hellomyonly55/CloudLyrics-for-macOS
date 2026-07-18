# CloudLyrics

[English](#english) · [中文](#中文)

## 中文

CloudLyrics 是一款支持 macOS 网易云音乐与酷狗音乐的菜单栏双行歌词工具。它可以显示当前歌词、下一行歌词或翻译，并提供基础播放控制。

> [!WARNING]
> 这是实验性、非官方项目，与网易云音乐、网易公司、酷狗音乐、腾讯音乐及 LRCLIB 均无隶属、认可或合作关系。播放器同步依赖网易云音乐的内部 CEF/webpack 实现，以及酷狗的 macOS 辅助功能界面和未公开的 MediaRemote 接口，客户端或系统更新后可能失效。

### 功能

- 菜单栏歌词窗口，支持单行和双行模式
- 颜色和位置设置
- 上一首、播放/暂停、下一首控制
- 网易云歌词与 LRCLIB 回退；酷狗优先读取客户端本地 KRC/LRC 歌词
- 双开时自动跟随实际正在输出声音的网易云或酷狗播放器
- 本地歌词缓存和登录时启动选项
- 支持 Apple Silicon 与 Intel Mac

### 系统要求

- macOS 14 Sonoma 或更高版本
- 网易云音乐 macOS 客户端 3.1.7，安装在 `/Applications/NeteaseMusic.app`；或酷狗音乐 3.3.2，安装在 `/Applications/酷狗音乐.app`
- 使用酷狗时需要授予 CloudLyrics“辅助功能”权限，用于只读获取播放进度及执行播放控制
- 不需要“自动化”、麦克风或录音权限
- 源码构建需要 Xcode/Swift 6

### 安装

#### GitHub Release

从 [Releases](https://github.com/hellomyonly55/CloudLyrics-for-MacOS/releases) 下载最新版 Universal DMG 或 ZIP。DMG 中可直接将 `CloudLyrics.app` 拖入“Applications”；ZIP 解压后请将应用移入系统“应用程序”文件夹（`/Applications`）。

当前应用使用 ad-hoc 签名且未经 Apple 公证。首次启动时请在 Finder 中右键应用并选择“打开”；如果仍被拦截，请前往“系统设置 → 隐私与安全”确认打开。请勿为了安装而全局关闭 Gatekeeper。

#### Homebrew

Homebrew Tap 公开后，可运行：

```bash
brew install --cask hellomyonly55/tap/cloudlyrics-for-macos
```

目前 `hellomyonly55/homebrew-tap` 仍为 Private，普通用户暂时无法使用此安装方式。

#### 从源码构建

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open /Applications/CloudLyrics.app
```

菜单栏状态项需要完整的 macOS 应用包，请不要将 `swift run CloudLyrics` 作为日常启动方式。

### 使用与卸载

CloudLyrics 不会自动启动播放器；请先打开网易云音乐或酷狗音乐。两者同时运行时，它优先根据 CoreAudio 的进程级输出状态跟随实际正在出声的播放器，与哪个应用位于前台无关；系统 Now Playing、播放器内部状态和最近有效选择仅用于无法区分时的回退。若两个播放器同时输出声音，则优先采用系统 Now Playing，再保持最近有效选择。

网易云成为实际播放方但尚未开启调试连接时，CloudLyrics 可能先正常退出网易云，再以仅绑定至 `127.0.0.1:9222` 的本地 CEF 调试模式重新启动。酷狗无需重启。

首次使用酷狗时，请前往“系统设置 → 隐私与安全性 → 辅助功能”，添加并启用 `/Applications/CloudLyrics.app`。macOS 的“自动化”列表不会显示 CloudLyrics，这是正常现象：当前版本不使用 Apple Events。

卸载时退出 CloudLyrics 并将 `/Applications/CloudLyrics.app` 移到废纸篓。缓存位于 `~/Library/Caches/CloudLyrics`，设置位于 `~/Library/Preferences/io.github.hellomyonly55.CloudLyrics.plist`；如需彻底清理，请分别手动删除这些明确路径。

### 隐私与安全

- CloudLyrics 不包含遥测或账号系统。
- 酷狗歌曲会优先在其本地容器的 `Caches/kgLyric` 目录中只读查找 KRC/LRC；本地缺失时，歌曲标题、歌手及可能的时长会发送至网易云音乐接口或 LRCLIB。
- 酷狗 3.3.2 不持续发布系统 Now Playing 元数据，因此 CloudLyrics 会通过 macOS 辅助功能 API 读取其可见播放栏文本并调用应用菜单中的播放控制；不会读取键盘输入，也不会控制酷狗以外的应用。
- 双播放器选择只读取 CoreAudio 提供的进程是否正在输出音频这一布尔状态；CloudLyrics 不录制、捕获或分析音频内容。
- 歌词缓存在当前用户的 `~/Library/Caches/CloudLyrics/lyrics.json`。
- 本地 CEF 调试接口仅绑定 `127.0.0.1:9222`，但同一台 Mac 上的其他本地进程仍可能访问该端口。不要在不可信的多用户环境中运行。
- 网易云歌词接口、客户端内部结构、酷狗辅助功能层级和 macOS MediaRemote 均不是稳定的公开 API。

安全问题请参阅 [SECURITY.md](SECURITY.md)。

### 测试与发布构建

```bash
swift test
./scripts/package-release.sh 0.2.1
```

发布脚本会在 `.build/releases/` 中生成 Universal DMG、ZIP 及各自的 SHA-256 文件。

### 已知限制

- 目前针对网易云音乐 3.1.7 与酷狗音乐 3.3.2 验证。
- 酷狗通过辅助功能读取整秒进度，CloudLyrics 使用亚秒插值及 0.5 秒歌词补偿；不同客户端版本仍可能存在轻微时间偏差。
- 两个播放器同时输出声音时，系统无法唯一推断用户意图，将使用 Now Playing 和最近有效选择作为回退。
- 固定使用本地端口 9222；如果端口被占用，播放器同步会失败。
- 未经 Apple 公证，首次启动需要用户确认。
- 非公开网易云歌词接口失效时会回退到 LRCLIB，但不保证所有歌曲都有同步歌词。

## English

CloudLyrics is an experimental macOS menu-bar lyrics app for NetEase Cloud Music and KuGou Music. It displays the current line together with the next line or translation and provides basic playback controls.

> [!WARNING]
> This is an unofficial project and is not affiliated with, endorsed by, or sponsored by NetEase Cloud Music, NetEase, KuGou Music, Tencent Music, or LRCLIB. Synchronization relies on internal NetEase CEF/webpack behavior, KuGou's macOS accessibility hierarchy, and an undocumented MediaRemote interface, and may break after client or system updates.

### Features

- Menu-bar lyrics window with single-line, next-line, and translation modes
- Configurable font, colors, outline, shadow, and position
- Previous, play/pause, and next controls
- NetEase lyrics with LRCLIB fallback; local KuGou KRC/LRC lyrics first for KuGou tracks
- Automatic switching to the NetEase or KuGou process that is actually producing audio
- Local lyrics cache and launch-at-login option
- Universal support for Apple Silicon and Intel Macs

### Requirements

- macOS 14 Sonoma or later
- NetEase Cloud Music 3.1.7 at `/Applications/NeteaseMusic.app`, or KuGou Music 3.3.2 at `/Applications/酷狗音乐.app`
- KuGou support requires granting CloudLyrics Accessibility permission for read-only progress observation and playback commands
- Automation, microphone, and audio-recording permissions are not required
- Xcode/Swift 6 for source builds

### Installation

#### GitHub Release

Download the latest Universal DMG or ZIP from [Releases](https://github.com/hellomyonly55/CloudLyrics-for-MacOS/releases). In the DMG, drag `CloudLyrics.app` to Applications. For the ZIP, extract it and move the app to the system Applications folder (`/Applications`).

The current build is ad-hoc signed and not notarized by Apple. On first launch, Control-click the app in Finder and choose Open. If macOS still blocks it, approve it in System Settings → Privacy & Security. Do not disable Gatekeeper globally.

#### Homebrew

After the Homebrew Tap becomes public, install with:

```bash
brew install --cask hellomyonly55/tap/cloudlyrics-for-macos
```

`hellomyonly55/homebrew-tap` is currently private, so this installation method is not yet available to regular users.

#### Build from source

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open /Applications/CloudLyrics.app
```

Use the full app bundle for daily use; `swift run CloudLyrics` does not provide the intended menu-bar app environment.

### Behavior and removal

CloudLyrics does not start a player automatically. Open NetEase or KuGou first. When both are running, it prioritizes CoreAudio's per-process output state and follows the player that is actually producing sound, regardless of which app is in front. System Now Playing, internal playback state, and the last valid selection are fallbacks only. If both players produce audio simultaneously, System Now Playing is preferred before retaining the last valid selection.

If NetEase becomes the audible player without an existing debugging connection, CloudLyrics may terminate it gracefully and relaunch it with a local CEF endpoint bound to `127.0.0.1:9222`. KuGou does not need to be restarted.

For first-time KuGou use, open System Settings → Privacy & Security → Accessibility, then add and enable `/Applications/CloudLyrics.app`. CloudLyrics does not appear under Automation because the current version does not use Apple Events.

To uninstall, quit CloudLyrics and move `/Applications/CloudLyrics.app` to Trash. Cache data is stored at `~/Library/Caches/CloudLyrics`, and preferences are stored at `~/Library/Preferences/io.github.hellomyonly55.CloudLyrics.plist`; remove these exact paths manually only if you want a full cleanup.

### Privacy and security

- CloudLyrics contains no telemetry or account system.
- KuGou tracks first use read-only KRC/LRC files under its local `Caches/kgLyric` container directory. If none match, title, artist, and possibly duration are sent to NetEase endpoints or LRCLIB.
- KuGou 3.3.2 does not continuously publish system Now Playing metadata, so CloudLyrics reads visible playback-bar text and invokes playback menu items through the macOS Accessibility API. It does not inspect keyboard input or control applications other than KuGou.
- Dual-player selection reads only CoreAudio's Boolean per-process audio-output state; CloudLyrics does not record, capture, or analyze audio content.
- Lyrics are cached locally in `~/Library/Caches/CloudLyrics/lyrics.json`.
- The CEF debugging endpoint is restricted to `127.0.0.1:9222`, but other local processes on the same Mac may still access that port. Avoid running it in an untrusted multi-user environment.
- NetEase endpoints, client internals, KuGou's accessibility hierarchy, and macOS MediaRemote are not stable public APIs.

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

### Tests and release build

```bash
swift test
./scripts/package-release.sh 0.2.1
```

The release script writes the Universal DMG, ZIP, and their SHA-256 files under `.build/releases/`.

### Known limitations

- NetEase Cloud Music 3.1.7 and KuGou Music 3.3.2 have been verified.
- KuGou exposes whole-second progress through Accessibility, so CloudLyrics applies sub-second interpolation and a 0.5-second lyric lead; other client versions may still have a small timing offset.
- If both players output audio simultaneously, macOS cannot uniquely infer intent; CloudLyrics falls back to System Now Playing and the last valid selection.
- Port 9222 is fixed; synchronization fails if another process occupies it.
- The app is not notarized and requires user approval on first launch.
- LRCLIB fallback cannot guarantee synchronized lyrics for every track.

## License

[MIT](LICENSE)
