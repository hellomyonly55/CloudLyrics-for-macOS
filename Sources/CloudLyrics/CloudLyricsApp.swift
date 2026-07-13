import AppKit
import Darwin
import QuartzCore
import SwiftUI

@main
@MainActor
enum CloudLyricsApp {
    private static var retainedDelegate: AppDelegate?

    static func main() {
        if CommandLine.arguments.contains("--diagnose-now-playing") {
            diagnoseNowPlaying()
            fflush(stdout)
            Darwin.exit(EXIT_SUCCESS)
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        delegate.installStatusItem()
        application.run()
    }

    private static func diagnoseNowPlaying() {
        let adapter = NetEaseAXPlayerAdapter()
        let deadline = Date().addingTimeInterval(3)
        var latest = adapter.snapshot()
        while Date() < deadline, latest.track == nil || latest.track?.title == "正在获取歌曲信息…" {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            latest = adapter.snapshot()
        }
        if let track = latest.track {
            print("READY\t\(track.title)\t\(track.artist)\t\(track.duration ?? 0)\t\(latest.progress)\t\(latest.isPlaying)")
        } else {
            switch latest.availability {
            case .notRunning: print("NOT_RUNNING")
            case .permissionRequired: print("PERMISSION_REQUIRED")
            case .connecting(let message): print("CONNECTING\t\(message)")
            case .incompatible(let message): print("UNAVAILABLE\t\(message)")
            case .ready: print("READY_WITHOUT_TRACK")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let statusLyricsView = StatusLyricsView()
    private var settingsWindow: NSPanel?
    private let settings = SettingsStoreReference.shared
    private let viewModel = AppViewModel()
    private var statusUpdateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
    }

    func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "CloudLyrics.StatusItem"
        item.isVisible = true
        statusItem = item
        guard let button = item.button else { return }
        button.title = ""
        button.image = nil
        button.toolTip = "CloudLyrics"
        button.action = nil
        button.target = nil
        statusLyricsView.onOpen = { [weak self] in self?.openSettings() }
        statusLyricsView.onSettings = { [weak self] in self?.openSettings() }
        statusLyricsView.onCommand = { [weak self] command in self?.viewModel.perform(command) }
        statusLyricsView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(statusLyricsView)
        NSLayoutConstraint.activate([
            statusLyricsView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 6),
            statusLyricsView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -6),
            statusLyricsView.topAnchor.constraint(equalTo: button.topAnchor, constant: 1),
            statusLyricsView.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1)
        ])
        updateStatusLyrics()
        let lyricTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusLyrics() }
        }
        lyricTimer.tolerance = 0.008
        RunLoop.main.add(lyricTimer, forMode: .common)
        statusUpdateTimer = lyricTimer
    }

    private func openSettings() {
        if let settingsWindow {
            if settingsWindow.isVisible {
                settingsWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 500),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "CloudLyrics 设置"
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(
            settings: settings,
            onDone: { [weak window] in window?.close() },
            onRefresh: { [weak self] in self?.viewModel.refresh(force: true) },
            onQuit: { NSApplication.shared.terminate(nil) }
        ))
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func updateStatusLyrics() {
        guard let item = statusItem else { return }
        let lines = viewModel.currentLines
        let appearance = settings.appearance
        let primary = lines.0.isEmpty ? "等待歌词…" : lines.0
        let secondary = lines.1 ?? " "
        statusLyricsView.update(
            primary: primary,
            secondary: secondary,
            primaryColor: NSColor(hex: appearance.primaryHex),
            secondaryColor: NSColor(hex: appearance.secondaryHex),
            alignment: appearance.alignment,
            primarySize: appearance.primarySize,
            secondarySize: appearance.secondarySize,
            lineSpacing: appearance.lineSpacing,
            horizontalOffset: appearance.horizontalOffset,
            showsSecondary: lines.1 != nil && appearance.mode != .single
        )
        item.length = min(max(appearance.width, 200), 700)
    }
}

@MainActor
private final class StatusLyricsView: NSView {
    private let primaryLabel = MarqueeLabel(string: "等待歌词…")
    private let secondaryLabel = MarqueeLabel(string: " ")
    private let lyricStack = NSStackView()
    private let controlsStack = NSStackView()
    private var centerConstraint: NSLayoutConstraint!
    private var controlsCenterConstraint: NSLayoutConstraint!
    private var isHoveringControls = false
    private var displayedPrimary: String?
    var onOpen: (() -> Void)?
    var onSettings: (() -> Void)?
    var onCommand: ((PlayerCommand) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        primaryLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        secondaryLabel.font = .systemFont(ofSize: 8)
        for label in [primaryLabel, secondaryLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        lyricStack.setViews([primaryLabel, secondaryLabel], in: .center)
        lyricStack.orientation = .vertical
        lyricStack.alignment = .centerX
        lyricStack.spacing = -1
        lyricStack.distribution = .fillEqually
        lyricStack.translatesAutoresizingMaskIntoConstraints = false
        lyricStack.wantsLayer = true
        lyricStack.layer?.masksToBounds = true
        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 4
        controlsStack.distribution = .gravityAreas
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.isHidden = true
        controlsStack.addArrangedSubview(commandButton("backward.fill", help: "上一首", command: .previous))
        controlsStack.addArrangedSubview(commandButton("playpause.fill", help: "播放/暂停", command: .playPause))
        controlsStack.addArrangedSubview(commandButton("forward.fill", help: "下一首", command: .next))
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(lyricStack)
        addSubview(controlsStack)
        centerConstraint = lyricStack.centerXAnchor.constraint(equalTo: centerXAnchor)
        controlsCenterConstraint = controlsStack.centerXAnchor.constraint(equalTo: lyricStack.centerXAnchor)
        NSLayoutConstraint.activate([
            lyricStack.widthAnchor.constraint(equalTo: widthAnchor),
            centerConstraint,
            lyricStack.topAnchor.constraint(equalTo: topAnchor),
            lyricStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            primaryLabel.widthAnchor.constraint(equalTo: lyricStack.widthAnchor),
            secondaryLabel.widthAnchor.constraint(equalTo: lyricStack.widthAnchor),
            controlsCenterConstraint,
            controlsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(primary: String, secondary: String, primaryColor: NSColor, secondaryColor: NSColor, alignment: LyricsAlignment, primarySize: Double, secondarySize: Double, lineSpacing: Double, horizontalOffset: Double, showsSecondary: Bool) {
        if let displayedPrimary, displayedPrimary != primary {
            animateLyricChange()
        }
        displayedPrimary = primary
        primaryLabel.stringValue = primary
        secondaryLabel.stringValue = secondary
        primaryLabel.textColor = primaryColor
        secondaryLabel.textColor = secondaryColor
        primaryLabel.font = .systemFont(ofSize: primarySize, weight: .semibold)
        secondaryLabel.font = .systemFont(ofSize: secondarySize)
        secondaryLabel.isHidden = !showsSecondary
        lyricStack.spacing = lineSpacing
        centerConstraint.constant = 0
        let safeOffset: Double
        switch alignment {
        case .leading: safeOffset = max(0, horizontalOffset)
        case .trailing: safeOffset = min(0, horizontalOffset)
        case .center: safeOffset = horizontalOffset
        }
        primaryLabel.horizontalOffset = CGFloat(safeOffset)
        secondaryLabel.horizontalOffset = CGFloat(safeOffset)
        controlsCenterConstraint.constant = CGFloat(safeOffset)
        let value: NSTextAlignment = alignment == .leading ? .left : alignment == .trailing ? .right : .center
        primaryLabel.alignment = value; secondaryLabel.alignment = value
    }

    private func animateLyricChange() {
        let transition = CATransition()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            transition.type = .fade
            transition.duration = 0.14
        } else {
            transition.type = .push
            transition.subtype = .fromBottom
            transition.duration = 0.26

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 0.45, 1]
            fade.keyTimes = [0, 0.44, 1]
            fade.duration = transition.duration
            fade.timingFunctions = [
                CAMediaTimingFunction(name: .easeIn),
                CAMediaTimingFunction(name: .easeOut)
            ]
            fade.isRemovedOnCompletion = true
            lyricStack.layer?.add(fade, forKey: "lyricFade")
        }
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        transition.isRemovedOnCompletion = true
        lyricStack.layer?.add(transition, forKey: "lyricChange")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHoveringControls = true
        lyricStack.isHidden = true
        controlsStack.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        isHoveringControls = false
        controlsStack.isHidden = true
        lyricStack.isHidden = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isHoveringControls else { onOpen?(); return }
    }

    override func rightMouseDown(with event: NSEvent) { onSettings?() }

    private func commandButton(_ symbol: String, help: String, command: PlayerCommand) -> NSButton {
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: help) ?? NSImage()
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold).applying(.init(paletteColors: [.white]))
        let image = base.withSymbolConfiguration(configuration) ?? base
        image.isTemplate = false
        let button = PressFeedbackButton(frame: .zero)
        button.image = image
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .white
        button.toolTip = help
        button.onPress = { [weak self] in self?.onCommand?(command) }
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 38),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
        return button
    }
}

private final class MarqueeLabel: NSView {
    private let textLayer = CATextLayer()
    private var marqueeSignature: String?

    var stringValue: String {
        didSet {
            guard oldValue != stringValue else { return }
            refreshText()
        }
    }
    var font = NSFont.systemFont(ofSize: NSFont.systemFontSize) {
        didSet {
            guard oldValue != font else { return }
            invalidateIntrinsicContentSize()
            refreshText()
        }
    }
    var textColor = NSColor.labelColor {
        didSet {
            guard oldValue != textColor else { return }
            refreshText()
        }
    }
    var alignment: NSTextAlignment = .center {
        didSet {
            guard oldValue != alignment else { return }
            marqueeSignature = nil
            needsLayout = true
        }
    }
    var horizontalOffset: CGFloat = 0 {
        didSet {
            guard oldValue != horizontalOffset else { return }
            marqueeSignature = nil
            needsLayout = true
        }
    }

    init(string: String) {
        stringValue = string
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.isWrapped = false
        textLayer.truncationMode = .none
        layer?.addSublayer(textLayer)
        refreshText()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ceil(font.ascender - font.descender + font.leading))
    }

    override func layout() {
        super.layout()
        layoutTextLayer()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        textLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func refreshText() {
        textLayer.string = attributedText
        marqueeSignature = nil
        needsLayout = true
    }

    private var attributedText: NSAttributedString {
        NSAttributedString(string: stringValue, attributes: [
            .font: font,
            .foregroundColor: textColor
        ])
    }

    private func layoutTextLayer() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let text = attributedText
        let horizontalInset: CGFloat = 4
        let availableWidth = max(0, bounds.width - horizontalInset * 2)
        let textWidth = ceil(text.size().width) + 2
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        let overflow = max(0, textWidth - availableWidth)
        let effectiveOffset = overflow > 0 ? 0 : clampedOffset(availableWidth: availableWidth, textWidth: textWidth)
        let signature = "\(stringValue)|\(font.pointSize)|\(availableWidth)|\(overflow)|\(alignment.rawValue)|\(effectiveOffset)"
        guard signature != marqueeSignature else { return }
        marqueeSignature = signature

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer.removeAnimation(forKey: "marquee")
        textLayer.transform = CATransform3DIdentity
        textLayer.frame = CGRect(
            x: horizontalInset + effectiveOffset,
            y: floor((bounds.height - textHeight) / 2),
            width: max(availableWidth, textWidth),
            height: textHeight
        )
        textLayer.alignmentMode = overflow > 0 ? .left : layerAlignment
        CATransaction.commit()

        guard overflow > 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let pause = 0.8
        let travel = max(1.5, Double(overflow) / 28)
        let duration = pause * 2 + travel * 2
        let marquee = CAKeyframeAnimation(keyPath: "transform.translation.x")
        marquee.values = [0, 0, -overflow, -overflow, 0, 0]
        marquee.keyTimes = [
            0,
            NSNumber(value: pause / duration),
            NSNumber(value: (pause + travel) / duration),
            NSNumber(value: (pause * 2 + travel) / duration),
            NSNumber(value: (pause * 2 + travel * 2) / duration),
            1
        ]
        marquee.duration = duration
        marquee.repeatCount = .infinity
        marquee.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .linear)
        ]
        textLayer.add(marquee, forKey: "marquee")
    }

    private func clampedOffset(availableWidth: CGFloat, textWidth: CGFloat) -> CGFloat {
        let slack = max(0, availableWidth - textWidth)
        switch alignment {
        case .left:
            return min(max(0, horizontalOffset), slack)
        case .right:
            return max(min(0, horizontalOffset), -slack)
        default:
            return min(max(horizontalOffset, -slack / 2), slack / 2)
        }
    }

    private var layerAlignment: CATextLayerAlignmentMode {
        switch alignment {
        case .left: .left
        case .right: .right
        default: .center
        }
    }
}

private final class PressFeedbackButton: NSButton {
    var onPress: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        target = self
        action = #selector(pressed)
        setButtonType(.momentaryChange)
    }

    required init?(coder: NSCoder) { nil }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        alphaValue = flag ? 0.45 : 1
        layer?.setAffineTransform(flag ? CGAffineTransform(scaleX: 0.88, y: 0.88) : .identity)
    }

    @objc private func pressed() { onPress?() }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let number = UInt64(value, radix: 16) ?? 0xFFFFFF
        self.init(
            calibratedRed: CGFloat((number >> 16) & 255) / 255,
            green: CGFloat((number >> 8) & 255) / 255,
            blue: CGFloat(number & 255) / 255,
            alpha: 1
        )
    }
}
