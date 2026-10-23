# CloudLyrics

[English](#english) · [中文](#中文)

## 中文

CloudLyrics 是一款支持 macOS 网易云音乐与酷狗音乐的菜单栏双行歌词工具。它可以显示当前歌词、下一行歌词或翻译，并提供基础播放控制。

> [!WARNING]
> 这是实验性、非官方项目，与网易云音乐、网易公司、酷狗音乐、腾讯音乐及 LRCLIB 均无隶属、认可或合作关系。播放器同步依赖播放器的本地数据格式、macOS 未公开的 MediaRemote 接口及辅助功能界面，播放器或系统更新后可能失效。

当前发行版：[CloudLyrics v1.0.0](https://github.com/hellomyonly55/CloudLyrics-for-macOS/releases/tag/v1.0.0)。

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
- 网易云音乐 macOS 客户端 3.1.8；或酷狗音乐 3.3.2，安装在 `/Applications/酷狗音乐.app`
- 网易云播放控制需要“辅助功能”权限；若系统拒绝读取网易云本地数据，还需在“完全磁盘访问权限”中允许 CloudLyrics，然后退出并重新打开应用
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

网易云无需任何额外启动参数。若显示“无法读取网易云播放数据”，请在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中允许 CloudLyrics，并退出后重新打开；这与辅助功能授权是两项不同权限。CloudLyrics 优先读取系统 Now Playing；对于不发布该信息的网易云 3.1.8，它会只读解析网易云本地保存的 `lastPlaying` 精确播放秒数，并从本地播放列表解析歌曲信息。两次原生进度更新之间只在内存中平滑显示，暂停和手动跳转会由下一次本地状态更新校准。CloudLyrics 不会为了建立连接而退出或重新启动网易云，也不会开启调试端口。

如需使用网易云播放控制，或首次使用酷狗，请前往“系统设置 → 隐私与安全性 → 辅助功能”，添加并启用 `/Applications/CloudLyrics.app`。应用使用临时签名，更新后如果旧授权失效，请重新启用 CloudLyrics 的辅助功能权限。macOS 的“自动化”列表不会显示 CloudLyrics，这是正常现象：当前版本不使用 Apple Events。

卸载时退出 CloudLyrics 并将 `/Applications/CloudLyrics.app` 移到废纸篓。缓存位于 `~/Library/Caches/CloudLyrics`，设置位于 `~/Library/Preferences/io.github.hellomyonly55.CloudLyrics.plist`；如需彻底清理，请分别手动删除这些明确路径。

### 歌词校准与电量

右键菜单栏歌词或点击控制按钮外的空白区域打开设置。设置分为「外观」「歌词同步」「通用」，外观修改有实时预览，单排模式会隐藏次行选项。

在「歌词同步」中，歌词慢了点「提前」，歌词快了点「延后」，每次调整 0.1 秒，范围为 ±5 秒，网易云和酷狗分别保存。默认提前 0.5 秒，校准不会改变播放器进度；前奏期间显示「前奏…」。重新获取歌词会跳过当前缓存，但歌词源版本不匹配时仍可能无法完全对齐。

默认「自动平衡」每 0.5 秒查询播放器，系统低电量模式下为 1 秒；「快速响应」为 0.2 秒，「优先省电」为 1 秒。两次查询之间通过内存时钟和下一句时间点触发换句，不需要提高播放器查询频率。暂停、跳转和切歌仍依赖播放器下一次提供状态；播放器未运行时每 3 秒检查一次。实际耗电与播放器、系统及歌词滚动情况有关，尚无电量基准测试。

### 隐私与安全

- CloudLyrics 不包含遥测或账号系统。
- 网易云歌曲信息优先通过系统 Now Playing 获取；在 3.1.8 上，CloudLyrics 只读解析网易云本地 `lastPlaying` 状态中的歌曲 ID、准确秒数和时长，并读取本地播放列表补全标题与歌手。控制按钮通过 MediaRemote 或网易云自己的辅助功能菜单执行。
- CloudLyrics 不向网易云进程注入代码、不修改网易云数据，也不开放本地调试端口。
- 酷狗歌曲会优先在其本地容器的 `Caches/kgLyric` 目录中只读查找 KRC/LRC；本地缺失时，歌曲标题、歌手及可能的时长会发送至网易云音乐接口或 LRCLIB。
- 酷狗 3.3.2 不持续发布系统 Now Playing 元数据，因此 CloudLyrics 会通过 macOS 辅助功能 API 读取其可见播放栏文本并调用应用菜单中的播放控制；不会读取键盘输入，也不会控制酷狗以外的应用。
- 双播放器选择只读取 CoreAudio 提供的进程是否正在输出音频这一布尔状态；CloudLyrics 不录制、捕获或分析音频内容。
- 歌词缓存在当前用户的 `~/Library/Caches/CloudLyrics/lyrics.json`。
- 网易云本地数据格式与歌词接口、播放器辅助功能层级和 macOS MediaRemote 均不是稳定的公开 API。

安全问题请参阅 [SECURITY.md](SECURITY.md)。

### 测试与发布构建

```bash
swift test
./scripts/package-release.sh 1.0.0
```

发布脚本会在 `.build/releases/` 中生成 Universal DMG、ZIP 及各自的 SHA-256 文件。

### 已知限制

- 目前针对网易云音乐 3.1.8 与酷狗音乐 3.3.2 验证。
- 网易云 3.1.8 的无参数同步依赖其未公开的本地 `lastPlaying` 格式；手动跳转后会在下一次原生进度写入时重新对齐，客户端升级后该格式仍可能变化。
- 酷狗通过辅助功能读取整秒进度，CloudLyrics 使用亚秒插值及默认 0.5 秒歌词补偿，可在「歌词同步」中分别校准；不同客户端版本仍可能存在时间偏差。
- 两个播放器同时输出声音时，系统无法唯一推断用户意图，将使用 Now Playing 和最近有效选择作为回退。
- 未经 Apple 公证，首次启动需要用户确认。
- 非公开网易云歌词接口失效时会回退到 LRCLIB，但不保证所有歌曲都有同步歌词。

## English

CloudLyrics is an experimental macOS menu-bar lyrics app for NetEase Cloud Music and KuGou Music. It displays the current line together with the next line or translation and provides basic playback controls.

> [!WARNING]
> This is an unofficial project and is not affiliated with, endorsed by, or sponsored by NetEase Cloud Music, NetEase, KuGou Music, Tencent Music, or LRCLIB. Synchronization relies on player-local data formats, an undocumented macOS MediaRemote interface, and accessibility hierarchies, and may break after player or system updates.

Current release: [CloudLyrics v1.0.0](https://github.com/hellomyonly55/CloudLyrics-for-macOS/releases/tag/v1.0.0).

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
- NetEase Cloud Music 3.1.8, or KuGou Music 3.3.2 at `/Applications/酷狗音乐.app`
- NetEase playback controls require Accessibility permission. If macOS denies access to NetEase local playback data, allow CloudLyrics in Full Disk Access and quit/reopen it.
- KuGou support requires Accessibility permission for read-only progress observation and playback commands
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

NetEase requires no additional launch arguments. If local data access is denied, enable CloudLyrics in System Settings → Privacy & Security → Full Disk Access, then quit and reopen it. This is separate from Accessibility permission. CloudLyrics prefers System Now Playing; for NetEase 3.1.8, which does not publish that state, it read-only decodes the exact playback seconds from NetEase's local `lastPlaying` state and resolves metadata from the local play queue. It only smooths display between native updates in memory; pause and manual seeks are corrected by the next local-state update. It never quits or relaunches NetEase to connect and does not open a debugging port.

To use NetEase playback controls, or for first-time KuGou use, open System Settings → Privacy & Security → Accessibility, then add and enable `/Applications/CloudLyrics.app`. Ad-hoc signed updates may require re-enabling CloudLyrics in Accessibility if the old permission stops applying. CloudLyrics does not appear under Automation because the current version does not use Apple Events.

To uninstall, quit CloudLyrics and move `/Applications/CloudLyrics.app` to Trash. Cache data is stored at `~/Library/Caches/CloudLyrics`, and preferences are stored at `~/Library/Preferences/io.github.hellomyonly55.CloudLyrics.plist`; remove these exact paths manually only if you want a full cleanup.

### Timing and power use

Right-click the menu-bar lyrics or click outside the playback buttons to open settings. Appearance, lyric synchronization, and general options have separate tabs, with a live appearance preview.

Adjust each player's lyric lead in 0.1-second steps (±5 seconds). Positive values show lyrics earlier; negative values delay them. The default is +0.5 seconds. Calibration does not change playback position. Instrumental intros display a waiting message until the first timestamp. Refreshing lyrics bypasses the cache; mismatched recording versions can still cause timing errors.

Balanced mode polls the player every 0.5 seconds (1 second in system Low Power Mode); Responsive uses 0.2 seconds and Energy Saving uses 1 second. Between polls, an in-memory clock schedules the next lyric boundary. Pause, seek, and track detection still depend on the next player state update. When no player is running, polling slows to every 3 seconds. Battery savings have not been benchmarked.

### Privacy and security

- CloudLyrics contains no telemetry or account system.
- NetEase metadata prefers System Now Playing. On 3.1.8, CloudLyrics read-only decodes the track ID, exact seconds, and duration from NetEase's local `lastPlaying` state, then reads its local play queue for title and artist metadata. Controls use MediaRemote or NetEase's own Accessibility menu.
- CloudLyrics does not inject code into NetEase, modify its data, or expose a local debugging port.
- KuGou tracks first use read-only KRC/LRC files under its local `Caches/kgLyric` container directory. If none match, title, artist, and possibly duration are sent to NetEase endpoints or LRCLIB.
- KuGou 3.3.2 does not continuously publish system Now Playing metadata, so CloudLyrics reads visible playback-bar text and invokes playback menu items through the macOS Accessibility API. It does not inspect keyboard input or control applications other than KuGou.
- Dual-player selection reads only CoreAudio's Boolean per-process audio-output state; CloudLyrics does not record, capture, or analyze audio content.
- Lyrics are cached locally in `~/Library/Caches/CloudLyrics/lyrics.json`.
- NetEase local data formats and endpoints, player accessibility hierarchies, and macOS MediaRemote are not stable public APIs.

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

### Tests and release build

```bash
swift test
./scripts/package-release.sh 1.0.0
```

The release script writes the Universal DMG, ZIP, and their SHA-256 files under `.build/releases/`.

### Known limitations

- NetEase Cloud Music 3.1.8 and KuGou Music 3.3.2 have been verified.
- NetEase 3.1.8's no-argument synchronization relies on its undocumented local `lastPlaying` format. A manual seek is reflected by the next native progress write, but a client update may change this format.
- KuGou exposes whole-second progress through Accessibility, so CloudLyrics applies sub-second interpolation and a configurable lyric lead (default +0.5 seconds); other client versions may still have a timing offset.
- If both players output audio simultaneously, macOS cannot uniquely infer intent; CloudLyrics falls back to System Now Playing and the last valid selection.
- The app is not notarized and requires user approval on first launch.
- LRCLIB fallback cannot guarantee synchronized lyrics for every track.

## License

[MIT](LICENSE)
