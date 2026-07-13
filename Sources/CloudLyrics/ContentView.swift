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
        case .notRunning: "网易云音乐未运行"
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("显示设置").font(.title2.bold())
                Spacer()
                Button("完成") { onDone?() ?? dismiss() }.keyboardShortcut(.defaultAction)
            }
            Picker("双排模式", selection: binding(\.mode)) { ForEach(TwoLineMode.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
            colorRow("主歌词颜色", keyPath: \AppearanceSettings.primaryHex)
            colorRow("次行颜色", keyPath: \AppearanceSettings.secondaryHex)
            slider("主歌词字号", value: binding(\.primarySize), range: 8...12, suffix: "pt")
            slider("次行字号", value: binding(\.secondarySize), range: 6...10, suffix: "pt")
            slider("行距", value: binding(\.lineSpacing), range: -2...2, suffix: "pt")
            slider("菜单栏宽度", value: binding(\.width), range: 200...700, suffix: "pt")
            slider("水平微调", value: binding(\.horizontalOffset), range: -120...120, suffix: "pt")
            Picker("对齐", selection: binding(\.alignment)) { ForEach(LyricsAlignment.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
            Toggle("登录时启动", isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
            Divider()
            HStack {
                Button("刷新歌词") { onRefresh?() }
                Spacer()
                Button("恢复默认设置", role: .destructive) { settings.reset() }
                Button("退出 CloudLyrics", role: .destructive) { onQuit?() }
            }
        }
        .padding(22).frame(width: 460)
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
