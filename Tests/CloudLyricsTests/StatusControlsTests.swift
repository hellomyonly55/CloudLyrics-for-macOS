import AppKit
import XCTest
@testable import CloudLyrics

@MainActor
final class StatusControlsTests: XCTestCase {
    func testRealMouseEventsRouteThreeControlsWithoutNativeButtonTracking() throws {
        _ = NSApplication.shared
        let view = StatusLyricsView(frame: NSRect(x: 0, y: 0, width: 287, height: 22))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSButton(frame: view.frame)
        host.addSubview(view)
        window.contentView = host
        view.mouseEntered(with: try event(.mouseMoved, point: .zero))
        view.layoutSubtreeIfNeeded()
        let regions = view.controlHitRegions
        XCTAssertEqual(regions.count, 3)
        var commands: [PlayerCommand] = []
        view.onCommand = { commands.append($0) }
        for region in regions {
            let center = NSPoint(x: region.rect.midX, y: region.rect.midY)
            XCTAssertEqual(view.command(at: center), region.command)
            XCTAssertTrue(host.hitTest(center) === view)
            let windowPoint = view.convert(center, to: nil)
            view.mouseDown(with: try event(.leftMouseDown, point: windowPoint))
            view.mouseUp(with: try event(.leftMouseUp, point: windowPoint))
        }
        XCTAssertEqual(commands, [.previous, .playPause, .next])
        var openedSettings = false
        view.onOpen = { openedSettings = true }
        view.activate(at: NSPoint(x: 2, y: 2))
        XCTAssertTrue(openedSettings)
        XCTAssertEqual(commands.count, 3)
        withExtendedLifetime(window) {}
    }

    func testDraggingBetweenControlsCancelsCommand() throws {
        _ = NSApplication.shared
        let view = StatusLyricsView(frame: NSRect(x: 0, y: 0, width: 228, height: 22))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.mouseEntered(with: try event(.mouseMoved, point: .zero))
        view.layoutSubtreeIfNeeded()
        var commands: [PlayerCommand] = []
        view.onCommand = { commands.append($0) }
        let regions = view.controlHitRegions
        let down = view.convert(NSPoint(x: regions[0].rect.midX, y: regions[0].rect.midY), to: nil)
        let up = view.convert(NSPoint(x: regions[1].rect.midX, y: regions[1].rect.midY), to: nil)
        view.mouseDown(with: try event(.leftMouseDown, point: down))
        view.mouseUp(with: try event(.leftMouseUp, point: up))
        XCTAssertTrue(commands.isEmpty)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
        withExtendedLifetime(window) {}
    }

    func testLyricsUseFullAvailableWidthBeforeAndAfterHover() throws {
        _ = NSApplication.shared
        let view = StatusLyricsView(frame: NSRect(x: 0, y: 0, width: 228, height: 22))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.update(primary: "这是一行比较长的歌词", secondary: "Translation", primaryColor: .white,
                    secondaryColor: .gray, alignment: .center, primarySize: 10,
                    secondarySize: 8, lineSpacing: -1, horizontalOffset: 0, showsSecondary: true)
        let stack = try XCTUnwrap(view.subviews.first as? NSStackView)
        for _ in 0..<2 {
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(stack.frame.width, view.bounds.width, accuracy: 0.5)
            for label in stack.arrangedSubviews {
                XCTAssertEqual(label.frame.width, view.bounds.width, accuracy: 0.5)
                XCTAssertGreaterThan(label.frame.height, 0)
            }
            view.mouseEntered(with: try event(.mouseMoved, point: .zero))
            view.mouseExited(with: try event(.mouseMoved, point: .zero))
        }
        withExtendedLifetime(window) {}
    }

    func testWidthFitsVisibleLyricsAndCapsLongLines() {
        let short = StatusLyricsView.preferredWidth(primary: "短歌词", secondary: nil,
            primarySize: 10, secondarySize: 8, maximumWidth: 360)
        XCTAssertEqual(short, 134)
        let long = StatusLyricsView.preferredWidth(primary: String(repeating: "歌词", count: 100),
            secondary: nil, primarySize: 10, secondarySize: 8, maximumWidth: 240)
        XCTAssertEqual(long, 240)
        let translated = StatusLyricsView.preferredWidth(primary: "短歌词",
            secondary: String(repeating: "翻译", count: 12), primarySize: 10,
            secondarySize: 8, maximumWidth: 360)
        XCTAssertGreaterThan(translated, short)
        XCTAssertLessThan(translated, 360)
    }

    func testControlsRemainSeparateAtCompactWidthAndRightClickOpensSettings() throws {
        _ = NSApplication.shared
        let view = StatusLyricsView(frame: NSRect(x: 6, y: 1, width: 122, height: 22))
        let host = NSButton(frame: NSRect(x: 0, y: 0, width: 134, height: 24))
        host.addSubview(view)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        view.mouseEntered(with: try event(.mouseMoved, point: .zero))
        view.layoutSubtreeIfNeeded()
        let regions = view.controlHitRegions
        for (index, region) in regions.enumerated() {
            XCTAssertTrue(view.bounds.contains(region.rect), "bounds=\(view.bounds) control=\(region.rect)")
            for other in regions.dropFirst(index + 1) {
                XCTAssertFalse(region.rect.intersects(other.rect))
            }
            XCTAssertTrue(host.hitTest(view.convert(NSPoint(x: region.rect.midX, y: region.rect.midY), to: host)) === view)
        }
        var commands: [PlayerCommand] = []
        var opened = false
        view.onCommand = { commands.append($0) }
        view.onOpen = { opened = true }
        view.rightMouseUp(with: try event(.rightMouseUp, point: .zero))
        XCTAssertTrue(opened)
        view.mouseUp(with: try event(.leftMouseUp, point: NSPoint(x: -100, y: -100)))
        XCTAssertTrue(commands.isEmpty)
        withExtendedLifetime(window) {}
    }

    func testNetEaseMenuTitlesSupportChineseAndEnglish() {
        XCTAssertTrue(NetEaseAccessibilityCommandBridge.menuTitles(for: .previous).contains("上一个"))
        XCTAssertTrue(NetEaseAccessibilityCommandBridge.menuTitles(for: .previous).contains("Previous"))
        XCTAssertTrue(NetEaseAccessibilityCommandBridge.menuTitles(for: .next).contains("下一首"))
        XCTAssertTrue(NetEaseAccessibilityCommandBridge.menuTitles(for: .next).contains("Next"))
        XCTAssertTrue(NetEaseAccessibilityCommandBridge.menuTitles(for: .playPause).contains("播放/暂停"))
        XCTAssertFalse(NetEaseAccessibilityCommandBridge.menuTitles(for: .previous).contains("Next"))
    }

    private func event(_ type: NSEvent.EventType, point: NSPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                         windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    }
}
