import AppKit
import XCTest
@testable import CloudLyrics

@MainActor
final class StatusControlsTests: XCTestCase {
    func testNativeStatusButtonOwnsHitsAndRoutesThreeCursorPositions() throws {
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
            XCTAssertTrue(host.hitTest(center) === host)
            view.activate(at: center)
        }
        XCTAssertEqual(commands, [.previous, .playPause, .next])
        var openedSettings = false
        view.onOpen = { openedSettings = true }
        view.activate(at: NSPoint(x: 2, y: 2))
        XCTAssertTrue(openedSettings)
        XCTAssertEqual(commands.count, 3)
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
