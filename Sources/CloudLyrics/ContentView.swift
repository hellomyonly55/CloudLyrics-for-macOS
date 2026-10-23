import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: SettingsStore
    let isPinned: Bool
    let togglePin: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header
            lyricArea
            progressArea
        }
        .padding(18)
        .frame(width: settings.appearance.width)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $viewModel.settingsPresented) {
            SettingsView(
                settings: settings,
                onRefresh: { viewModel.refresh(force: true) },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.snapshot.track?.title ?? "CloudLyrics").font(.headline).lineLimit(1)
                Text(viewModel.snapshot.track?.artist ?? statusText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button(action: togglePin) { Image(systemName: isPinned ? "pin.fill" : "pin") }
                .buttonStyle(.plain).help(isPinned ? "取消固定" : "固定弹窗")
        }
    }

    private var lyricArea: some View {
        let lines = viewModel.currentLines
        let appearance = settings.appearance
        return VStack(alignment: appearance.alignment.frameAlignment.horizontal, spacing: appearance.lineSpacing) {
            Text(lines.0.isEmpty ? "暂无歌词" : lines.0)
                .font(.system(size: appearance.primarySize, weight: .semibold))
                .foregroundStyle(Color(hex: appearance.primaryHex))
                .frame(maxWidth: .infinity, alignment: appearance.alignment.frameAlignment)
            if let secondary = lines.1, !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: appearance.secondarySize))
                    .foregroundStyle(Color(hex: appearance.secondaryHex))
                    .frame(maxWidth: .infinity, alignment: appearance.alignment.frameAlignment)
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(appearance.alignment.textAlignment)
        .frame(minHeight: 92)
        .animation(.easeOut(duration: 0.18), value: lines.0)
    }

    @ViewBuilder private var progressArea: some View {
        if let duration = viewModel.snapshot.track?.duration, duration > 0 {
            let progress = viewModel.snapshot.normalizedProgress
            VStack(spacing: 4) {
                ProgressView(value: progress, total: duration)
                HStack { Text(clock(progress)); Spacer(); Text(clock(duration)) }
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch viewModel.snapshot.availability {
        case .ready: viewModel.message
        case .permissionRequired: "等待辅助功能授权"
        case .notRunning: "网易云音乐与酷狗音乐均未运行"
        case .connecting(let text): text
        case .incompatible(let text): text
        }
    }

    private func clock(_ value: TimeInterval) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}

private extension Alignment {
    var horizontal: HorizontalAlignment {
        if self == .leading { return .leading }
        if self == .trailing { return .trailing }
        return .center
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    var onDone: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CloudLyrics 设置").font(.title2.bold())
                Spacer()
                Button("完成") { onDone?() ?? dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(20)
            TabView {
                appearanceTab.tabItem { Label("外观", systemImage: "textformat") }
                synchronizationTab.tabItem { Label("歌词同步", systemImage: "clock.arrow.circlepath") }
                generalTab.tabItem { Label("通用", systemImage: "gearshape") }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 560, height: 590)
    }

    private var appearanceTab: some View {
        VStack(spacing: 12) {
            VStack(spacing: settings.appearance.lineSpacing) {
                Text("让歌词，刚好跟上这一刻")
                    .font(.system(size: settings.appearance.primarySize, weight: .semibold))
                    .foregroundStyle(Color(hex: settings.appearance.primaryHex))
                if settings.appearance.mode != .single {
                    Text(settings.appearance.mode == .translation ? "Let the music carry you" : "下一句歌词会在这里显示")
                        .font(.system(size: settings.appearance.secondarySize))
                        .foregroundStyle(Color(hex: settings.appearance.secondaryHex))
                }
            }
            .frame(width: settings.appearance.width - 20, height: 30, alignment: settings.appearance.alignment.frameAlignment)
            .offset(x: settings.appearance.horizontalOffset)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .clipped()
            Text("菜单栏预览 · 修改后立即生效").font(.caption).foregroundStyle(.secondary)
            Form {
                Section("歌词内容") {
                    Picker("显示模式", selection: binding(\.mode)) {
                        ForEach(TwoLineMode.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("文字与颜色") {
                    colorRow("主歌词颜色", keyPath: \AppearanceSettings.primaryHex)
                    slider("主歌词字号", value: binding(\.primarySize), range: 8...12, suffix: "pt")
                    if settings.appearance.mode != .single {
                        colorRow("次行颜色", keyPath: \AppearanceSettings.secondaryHex)
                        slider("次行字号", value: binding(\.secondarySize), range: 6...10, suffix: "pt")
                        slider("行距", value: binding(\.lineSpacing), range: -2...2, suffix: "pt")
                    }
                }
                Section("菜单栏布局") {
                    slider("占用宽度", value: binding(\.width), range: 200...700, suffix: "pt")
                    Picker("对齐方式", selection: binding(\.alignment)) {
                        ForEach(LyricsAlignment.allCases) { Text($0.label).tag($0) }
                    }
                    slider("水平微调", value: binding(\.horizontalOffset), range: -120...120, suffix: "pt")
                }
            }.formStyle(.grouped)
            Button("恢复默认外观") { settings.reset() }
        }.padding(12)
    }

    private var synchronizationTab: some View {
        Form {
            Section("歌词时间校准") {
                Text("歌词慢了，点「提前」；歌词快了，点「延后」。每次调整 0.1 秒，分别保存到对应播放器。")
                    .font(.callout).foregroundStyle(.secondary)
                timingRow("网易云音乐", path: \.neteaseLead)
                timingRow("酷狗音乐", path: \.kugouLead)
                Text("正数表示提前显示，负数表示延后。校准对该播放器的所有歌曲生效；版本不匹配的歌词可尝试重新获取。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("重新获取当前歌词") { onRefresh?() }
            }
            Section("响应与电量") {
                Picker("运行模式", selection: syncBinding(\.refreshMode)) {
                    ForEach(RefreshMode.allCases) { Text($0.label).tag($0) }
                }
                Text("自动平衡：播放时每 0.5 秒查询一次；系统低电量模式下每 1 秒一次。快速响应：每 0.2 秒。优先省电：每 1 秒。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("换句在两次查询之间由本地时钟触发。暂停和切歌的发现速度受查询间隔及播放器提供的信息限制。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("恢复默认同步设置") { settings.resetSynchronization() }
        }.formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动", isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                if let error = settings.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
            }
            Section("菜单栏操作") {
                Text("移入歌词区域显示播放控制；点击空白处或右键打开设置。")
                    .foregroundStyle(.secondary)
            }
            Section("权限") {
                Text("酷狗歌词同步和播放器控制需要辅助功能权限。网易云歌词同步还可能受到系统文件访问保护限制。")
                    .foregroundStyle(.secondary)
                Text("如果出现「无法读取网易云播放数据」，还需在完全磁盘访问权限中允许 CloudLyrics，再退出并重新打开应用。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("打开完全磁盘访问权限设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("打开辅助功能设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Section { Button("退出 CloudLyrics") { onQuit?() } }
        }.formStyle(.grouped)
    }

    private func syncBinding<T>(_ path: WritableKeyPath<SynchronizationSettings, T>) -> Binding<T> {
        Binding(get: { settings.synchronization[keyPath: path] }, set: { settings.synchronization[keyPath: path] = $0 })
    }

    private func timingRow(_ title: String, path: WritableKeyPath<SynchronizationSettings, Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack {
                Button("延后 0.1 秒") { adjustTiming(path, by: -0.1) }
                Spacer()
                Text(String(format: "%+.1f 秒", settings.synchronization[keyPath: path])).monospacedDigit()
                Spacer()
                Button("提前 0.1 秒") { adjustTiming(path, by: 0.1) }
            }
            Slider(value: syncBinding(path), in: -5...5, step: 0.1).accessibilityLabel("\(title)歌词时间校准")
        }.padding(.vertical, 6)
    }

    private func adjustTiming(_ path: WritableKeyPath<SynchronizationSettings, Double>, by amount: Double) {
        settings.synchronization[keyPath: path] = min(5, max(-5, ((settings.synchronization[keyPath: path] + amount) * 10).rounded() / 10))
    }

    private func binding<T>(_ path: WritableKeyPath<AppearanceSettings, T>) -> Binding<T> {
        Binding(get: { settings.appearance[keyPath: path] }, set: { settings.appearance[keyPath: path] = $0 })
    }

    private func colorRow(_ title: String, keyPath: WritableKeyPath<AppearanceSettings, String>) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(get: { Color(hex: settings.appearance[keyPath: keyPath]) }, set: { settings.appearance[keyPath: keyPath] = $0.hexString }))
            TextField("#FFFFFF", text: binding(keyPath)).textFieldStyle(.roundedBorder).frame(width: 92)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack { Text(title).frame(width: 90, alignment: .leading); Slider(value: value, in: range); Text("\(Int(value.wrappedValue)) \(suffix)").monospacedDigit().frame(width: 52, alignment: .trailing) }
    }
}

private extension Color {
    var hexString: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }
}
