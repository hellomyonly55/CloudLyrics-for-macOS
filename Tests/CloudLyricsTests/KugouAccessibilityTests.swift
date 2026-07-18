import XCTest
@testable import CloudLyrics

final class KugouAccessibilityTests: XCTestCase {
    func testParsesBottomPlaybackBar() {
        let entries = [
            KugouAXTextEntry(value: "search result", position: .init(x: 20, y: 100)),
            KugouAXTextEntry(value: "Song - Singer", position: .init(x: 350, y: 770)),
            KugouAXTextEntry(value: "1:02 ", position: .init(x: 800, y: 773)),
            KugouAXTextEntry(value: "/ 3:57", position: .init(x: 835, y: 773))
        ]
        XCTAssertEqual(KugouAXSnapshotParser.parse(entries), .init(title: "Song", artist: "Singer", progress: 62, duration: 237))
    }

    func testUsesLastSeparatorForHyphenatedTitle() {
        let entries = [
            KugouAXTextEntry(value: "Part 1 - Part 2 - Artist", position: .init(x: 350, y: 770)),
            KugouAXTextEntry(value: "0:01", position: .init(x: 800, y: 773)),
            KugouAXTextEntry(value: "/ 4:00", position: .init(x: 835, y: 773))
        ]
        XCTAssertEqual(KugouAXSnapshotParser.parse(entries)?.title, "Part 1 - Part 2")
        XCTAssertEqual(KugouAXSnapshotParser.parse(entries)?.artist, "Artist")
    }

    func testRejectsIncompletePlaybackBar() {
        XCTAssertNil(KugouAXSnapshotParser.parse([.init(value: "Song - Singer", position: .zero)]))
    }

    func testLocatorUsesCachedPlaybackNodesAfterInitialScan() {
        var locator = KugouAccessibilityLocator<Int>()
        var values: [Int: KugouAXTextEntry] = [
            10: .init(value: "Song - Singer", position: .init(x: 10, y: 20)),
            11: .init(value: "01:02", position: .init(x: 100, y: 20)),
            12: .init(value: "/ 03:57", position: .init(x: 140, y: 20))
        ]
        var scans = 0
        let scan = {
            scans += 1
            return values.keys.sorted().map { KugouAccessibilityLocator<Int>.Candidate(entry: values[$0]!, node: $0) }
        }

        XCTAssertEqual(locator.resolve(read: { values[$0] }, scan: scan)?.progress, 62)
        values[11]?.value = "01:03"
        XCTAssertEqual(locator.resolve(read: { values[$0] }, scan: scan)?.progress, 63)
        XCTAssertEqual(scans, 1)
    }

    func testLocatorFallsBackToFullScanWhenCachedNodeBecomesInvalid() {
        var locator = KugouAccessibilityLocator<Int>()
        var values: [Int: KugouAXTextEntry] = [
            1: .init(value: "Old - Singer", position: .init(x: 10, y: 20)),
            2: .init(value: "00:10", position: .init(x: 100, y: 20)),
            3: .init(value: "/ 03:00", position: .init(x: 140, y: 20))
        ]
        var scans = 0
        func scan() -> [KugouAccessibilityLocator<Int>.Candidate] {
            scans += 1
            return values.keys.sorted().map { .init(entry: values[$0]!, node: $0) }
        }
        XCTAssertEqual(locator.resolve(read: { values[$0] }, scan: scan)?.title, "Old")

        values = [
            4: .init(value: "New - Artist", position: .init(x: 10, y: 30)),
            5: .init(value: "00:01", position: .init(x: 100, y: 30)),
            6: .init(value: "/ 04:00", position: .init(x: 140, y: 30))
        ]
        XCTAssertEqual(locator.resolve(read: { values[$0] }, scan: scan)?.title, "New")
        XCTAssertEqual(scans, 2)
    }

    func testInterpolatesWholeSecondProgressSamples() {
        var estimator = KugouProgressEstimator()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(estimator.update(trackKey: "song", rawProgress: 10, now: start).progress, 10, accuracy: 0.001)
        _ = estimator.update(trackKey: "song", rawProgress: 10, now: start.addingTimeInterval(0.9))
        let tick = estimator.update(trackKey: "song", rawProgress: 11, now: start.addingTimeInterval(1.0))
        XCTAssertTrue(tick.isPlaying)
        XCTAssertEqual(tick.progress, 11.05, accuracy: 0.001)

        let betweenTicks = estimator.update(trackKey: "song", rawProgress: 11, now: start.addingTimeInterval(1.4))
        XCTAssertEqual(betweenTicks.progress, 11.45, accuracy: 0.001)
    }

    func testInterpolationDoesNotRunPastUnconfirmedSecond() {
        var estimator = KugouProgressEstimator()
        let start = Date(timeIntervalSince1970: 2_000)
        _ = estimator.update(trackKey: "song", rawProgress: 20, now: start)
        _ = estimator.update(trackKey: "song", rawProgress: 21, now: start.addingTimeInterval(0.1))
        _ = estimator.update(trackKey: "song", rawProgress: 21, now: start.addingTimeInterval(1.0))

        let stalled = estimator.update(trackKey: "song", rawProgress: 21, now: start.addingTimeInterval(2.0))
        XCTAssertFalse(stalled.isPlaying)
        XCTAssertEqual(stalled.progress, 21.95, accuracy: 0.001)
    }

    func testSeekAndTrackChangeResetInterpolation() {
        var estimator = KugouProgressEstimator()
        let start = Date(timeIntervalSince1970: 3_000)
        _ = estimator.update(trackKey: "first", rawProgress: 50, now: start)
        _ = estimator.update(trackKey: "first", rawProgress: 51, now: start.addingTimeInterval(0.1))
        XCTAssertEqual(estimator.update(trackKey: "first", rawProgress: 12, now: start.addingTimeInterval(0.2)).progress, 12, accuracy: 0.001)

        let changed = estimator.update(trackKey: "second", rawProgress: 3, now: start.addingTimeInterval(0.3))
        XCTAssertFalse(changed.isPlaying)
        XCTAssertEqual(changed.progress, 3, accuracy: 0.001)
    }
}
