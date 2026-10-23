import XCTest
@testable import CloudLyrics

final class ModelsTests: XCTestCase {
    func testPlayerNamespacedKeysAndLegacyDecode() throws {
        let netease = TrackIdentity(title: "Same", artist: "Singer", sourceID: "123", player: .netease)
        let kugou = TrackIdentity(title: "Same", artist: "Singer", sourceID: "123", player: .kugou)
        XCTAssertEqual(netease.normalizedKey, "netease:123")
        XCTAssertEqual(kugou.normalizedKey, "kugou:123")
        let legacy = try JSONDecoder().decode(TrackIdentity.self, from: Data(#"{"title":"Old","artist":"Artist","sourceID":"9"}"#.utf8))
        XCTAssertEqual(legacy.player, .netease)
        XCTAssertEqual(legacy.normalizedKey, "netease:9")
    }

    func testAutomaticPlayerSelectionFollowsActiveAndKeepsPrevious() {
        XCTAssertEqual(AutomaticPlayerSelection.choose(activeBundleIdentifier: PlayerBundleIdentifiers.kugou, previous: .netease, neteaseRunning: true, kugouRunning: true), .kugou)
        XCTAssertEqual(AutomaticPlayerSelection.choose(activeBundleIdentifier: PlayerBundleIdentifiers.netease, previous: .kugou, neteaseRunning: true, kugouRunning: true), .netease)
        XCTAssertEqual(AutomaticPlayerSelection.choose(activeBundleIdentifier: nil, previous: .kugou, neteaseRunning: true, kugouRunning: true), .kugou)
        XCTAssertEqual(AutomaticPlayerSelection.choose(activeBundleIdentifier: nil, previous: .netease, neteaseRunning: true, kugouRunning: true, kugouPlaying: true), .kugou)
        XCTAssertEqual(AutomaticPlayerSelection.choose(activeBundleIdentifier: nil, previous: nil, neteaseRunning: false, kugouRunning: true), .kugou)
        XCTAssertNil(AutomaticPlayerSelection.choose(activeBundleIdentifier: nil, previous: .kugou, neteaseRunning: false, kugouRunning: false))
    }

    func testFrontmostPlayerIsUsedOnlyAsFallback() {
        XCTAssertEqual(
            AutomaticPlayerSelection.choose(
                activeBundleIdentifier: nil,
                frontmostBundleIdentifier: PlayerBundleIdentifiers.netease,
                previous: .kugou,
                neteaseRunning: true,
                kugouRunning: true
            ),
            .netease
        )
        XCTAssertEqual(
            AutomaticPlayerSelection.choose(
                activeBundleIdentifier: nil,
                previous: .kugou,
                neteaseRunning: true,
                kugouRunning: true,
                neteasePlaying: true
            ),
            .netease
        )
    }

    func testBackgroundAudioOverridesFrontmostPlayer() {
        XCTAssertEqual(
            AutomaticPlayerSelection.choose(
                activeBundleIdentifier: nil,
                frontmostBundleIdentifier: PlayerBundleIdentifiers.kugou,
                previous: .kugou,
                neteaseRunning: true,
                kugouRunning: true,
                neteaseAudible: true,
                kugouAudible: false
            ),
            .netease
        )
        XCTAssertEqual(
            AutomaticPlayerSelection.choose(
                activeBundleIdentifier: nil,
                frontmostBundleIdentifier: PlayerBundleIdentifiers.netease,
                previous: .netease,
                neteaseRunning: true,
                kugouRunning: true,
                neteaseAudible: false,
                kugouAudible: true
            ),
            .kugou
        )
    }

    func testTrackNormalizationRemovesVersionAndWhitespace() {
        XCTAssertEqual(TrackIdentity.normalize("晴天（Live 版） "), "晴天")
        XCTAssertEqual(TrackIdentity.normalize("Hello [Remastered]"), "hello")
    }

    func testLineIndexAtBoundariesAndEnd() {
        let track = TrackIdentity(title: "t", artist: "a")
        let document = LyricsDocument(track: track, lines: [
            .init(time: 1, text: "one"), .init(time: 3, text: "three"), .init(time: 5, text: "five")
        ], source: "test")
        XCTAssertNil(document.lineIndex(at: 0))
        XCTAssertEqual(document.lineIndex(at: 3), 1)
        XCTAssertEqual(document.lineIndex(at: 100), 2)
    }

    func testOffsetAffectsLookup() {
        let track = TrackIdentity(title: "t", artist: "a")
        let document = LyricsDocument(track: track, lines: [.init(time: 1, text: "one"), .init(time: 2, text: "two")], source: "test", offset: 0.5)
        XCTAssertEqual(document.lineIndex(at: 2.4), 0)
        XCTAssertEqual(document.lineIndex(at: 2.5), 1)
    }

    func testPlayerProgressClampsAtTrackEnd() {
        let track = TrackIdentity(title: "t", artist: "a", duration: 203)
        let snapshot = PlayerSnapshot(availability: .ready, track: track, progress: 973, isPlaying: true)
        XCTAssertEqual(snapshot.normalizedProgress, 203, accuracy: 0.001)
    }

    func testPlayerSpecificLyricLeadCompensatesDisplayLatency() {
        let track = TrackIdentity(title: "t", artist: "a", duration: 203, player: .kugou)
        let kugou = PlayerSnapshot(availability: .ready, track: track, progress: 10, isPlaying: true, player: .kugou)
        let netease = PlayerSnapshot(
            availability: .ready,
            track: .init(title: "t", artist: "a", duration: 203, player: .netease),
            progress: 10,
            isPlaying: true,
            player: .netease
        )
        XCTAssertEqual(kugou.lyricProgress, 10.5, accuracy: 0.001)
        XCTAssertEqual(netease.lyricProgress, 10.5, accuracy: 0.001)
    }

    func testNetEaseLyricLeadDoesNotAdvancePausedPlayback() {
        let snapshot = PlayerSnapshot(
            availability: .ready,
            track: .init(title: "t", artist: "a", duration: 203, player: .netease),
            progress: 10,
            isPlaying: false,
            player: .netease
        )
        XCTAssertEqual(snapshot.lyricProgress, 10, accuracy: 0.001)
    }

    func testSystemProgressAdvancesWithoutMediaTimestamp() {
        let state = SystemNowPlayingState(
            processIdentifier: 1,
            title: "Song",
            artist: "Artist",
            elapsed: 10,
            rate: 1,
            timestamp: nil,
            observedAt: Date().addingTimeInterval(-2)
        )
        XCTAssertEqual(state.currentProgress, 12, accuracy: 0.1)
    }

    func testMediaRemoteRefreshPolicyUsesNotificationsAndSafetyRefresh() {
        var policy = MediaRemoteRefreshPolicy(safetyInterval: 0.5)
        let start = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(policy.shouldRefresh(at: start))
        XCTAssertFalse(policy.shouldRefresh(at: start.addingTimeInterval(0.2)))
        policy.markDirty()
        XCTAssertTrue(policy.shouldRefresh(at: start.addingTimeInterval(0.21)))
        XCTAssertFalse(policy.shouldRefresh(at: start.addingTimeInterval(0.4)))
        XCTAssertTrue(policy.shouldRefresh(at: start.addingTimeInterval(0.8)))
    }

    func testTranslationModeUsesTranslationWhenAvailable() {
        let document = lyrics([.init(time: 0, text: "原文", translation: "Translation"), .init(time: 5, text: "下一句")])
        XCTAssertEqual(LyricPresentation.make(document: document, index: 0, mode: .translation), .init(primary: "原文", secondary: "Translation"))
    }

    func testTranslationModeFallsBackToNextLine() {
        let document = lyrics([.init(time: 0, text: "当前句"), .init(time: 5, text: "下一句")])
        XCTAssertEqual(LyricPresentation.make(document: document, index: 0, mode: .translation), .init(primary: "当前句", secondary: "下一句"))
        XCTAssertEqual(LyricPresentation.make(document: document, index: 1, mode: .translation), .init(primary: "下一句", secondary: nil))
    }

    func testSingleAndNextLineModes() {
        let document = lyrics([.init(time: 0, text: "当前句", translation: "翻译"), .init(time: 5, text: "下一句")])
        XCTAssertEqual(LyricPresentation.make(document: document, index: 0, mode: .single), .init(primary: "当前句", secondary: nil))
        XCTAssertEqual(LyricPresentation.make(document: document, index: 0, mode: .nextLine), .init(primary: "当前句", secondary: "下一句"))
    }

    func testSystemNowPlayingBuildsNetEaseSnapshotWithoutCEFState() {
        let state = SystemNowPlayingState(
            processIdentifier: 42,
            title: "Song",
            artist: "Artist",
            duration: 180,
            elapsed: 12,
            rate: 0,
            timestamp: nil,
            sourceID: "12345",
            observedAt: Date(timeIntervalSince1970: 10_000)
        )

        let snapshot = state.snapshot(player: .netease, audible: true)
        XCTAssertEqual(snapshot.availability, .ready)
        XCTAssertEqual(snapshot.track, .init(title: "Song", artist: "Artist", duration: 180, sourceID: "12345", player: .netease))
        XCTAssertEqual(snapshot.progress, 12, accuracy: 0.001)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(snapshot.player, .netease)
    }

    func testNetEaseLastPlayingDecoderReadsExactNativeProgress() throws {
        let encoded = "rZkiW6jJrOlRkCHQA/EsJ0HewSOh0BwHO2coy/ZELY4Dek+Uvk+dHTzDdHVj8UCwKg+K92TaaWgLE/DH8G3a2+HVurJhcZDPVjYXD968Ji0F9eFh17/H1RbbCT/9nCfNx/Gzjw1GoKv6+n3IJvel6P2HrcXkmwIesuwb4Ghmuao="
        let state = try XCTUnwrap(NetEaseLastPlayingDecoder.decode(base64: encoded))
        XCTAssertEqual(state.current, 76, accuracy: 0.001)
        XCTAssertEqual(state.resourceDuration, 236)
        XCTAssertEqual(state.resourceID, "3343899755")
        XCTAssertEqual(state.trackID, "3343899755")
    }

    func testNetEaseLastPlayingDecoderFindsValueInsideLevelDBBytes() throws {
        let encoded = "rZkiW6jJrOlRkCHQA/EsJ0HewSOh0BwHO2coy/ZELY4Dek+Uvk+dHTzDdHVj8UCwKg+K92TaaWgLE/DH8G3a2+HVurJhcZDPVjYXD968Ji0F9eFh17/H1RbbCT/9nCfNx/Gzjw1GoKv6+n3IJvel6P2HrcXkmwIesuwb4Ghmuao="
        let bytes = Data("\u{1}lastPlayingT\(encoded)C\u{0}META:orpheus://orpheus".utf8)
        let state = try XCTUnwrap(NetEaseLastPlayingDecoder.states(in: bytes).last?.state)
        XCTAssertEqual(state.current, 76, accuracy: 0.001)
        XCTAssertEqual(state.resourceID, "3343899755")
    }

    func testNetEaseLiveLogStateIsNotReplacedByStaleCompactedTable() {
        var cache = NetEaseLastPlayingStateCache()
        let bootstrap = NetEaseLastPlayingState(
            current: 10,
            resourceDuration: 100,
            resourceID: "1",
            trackID: "1"
        )
        let live = NetEaseLastPlayingState(
            current: 80,
            resourceDuration: 100,
            resourceID: "1",
            trackID: "1"
        )
        let staleCompactedValue = NetEaseLastPlayingState(
            current: 12,
            resourceDuration: 100,
            resourceID: "1",
            trackID: "1"
        )

        XCTAssertEqual(cache.bootstrapFromTable(bootstrap).current, 10)
        XCTAssertEqual(cache.observeLog(live).current, 80)
        XCTAssertEqual(cache.bootstrapFromTable(staleCompactedValue).current, 80)
        XCTAssertEqual(cache.state?.current, 80)
    }

    func testNetEaseProgressEstimatorFollowsExactProgressAndSeek() {
        var estimator = NetEaseProgressEstimator()
        let start = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(
            estimator.update(songID: "1", duration: 100, exactProgress: 8, isPlaying: true, now: start),
            8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            estimator.update(songID: "1", duration: 100, exactProgress: 8, isPlaying: true, now: start.addingTimeInterval(0.5)),
            8.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            estimator.update(songID: "1", duration: 100, exactProgress: 9, isPlaying: true, now: start.addingTimeInterval(1)),
            9,
            accuracy: 0.001
        )
        XCTAssertEqual(
            estimator.update(songID: "1", duration: 100, exactProgress: 40, isPlaying: true, now: start.addingTimeInterval(1.25)),
            40,
            accuracy: 0.001
        )
        XCTAssertEqual(
            estimator.update(songID: "1", duration: 100, exactProgress: 40, isPlaying: false, now: start.addingTimeInterval(1.5)),
            40,
            accuracy: 0.001
        )
    }

    func testNetEaseProgressDoesNotFlashBackAcrossLyricBoundary() {
        var estimator = NetEaseProgressEstimator()
        let start = Date(timeIntervalSince1970: 10_000)
        let document = LyricsDocument(
            track: .init(title: "t", artist: "a"),
            lines: [.init(time: 0, text: "previous"), .init(time: 10.1, text: "next")],
            source: "test"
        )

        _ = estimator.update(songID: "1", duration: 100, exactProgress: 9, isPlaying: true, now: start)
        let interpolated = estimator.update(
            songID: "1",
            duration: 100,
            exactProgress: 9,
            isPlaying: true,
            now: start.addingTimeInterval(1.2)
        )
        let delayedNativeSample = estimator.update(
            songID: "1",
            duration: 100,
            exactProgress: 10,
            isPlaying: true,
            now: start.addingTimeInterval(1.21)
        )

        XCTAssertEqual(interpolated, 10.2, accuracy: 0.001)
        XCTAssertEqual(delayedNativeSample, 10.21, accuracy: 0.001)
        XCTAssertEqual(document.lineIndex(at: interpolated), 1)
        XCTAssertEqual(document.lineIndex(at: delayedNativeSample), 1)

        let unconfirmedBackwardSample = estimator.update(
            songID: "1",
            duration: 100,
            exactProgress: 4,
            isPlaying: true,
            now: start.addingTimeInterval(1.4)
        )
        XCTAssertGreaterThanOrEqual(unconfirmedBackwardSample, delayedNativeSample)
        let confirmedBackwardSeek = estimator.update(
            songID: "1",
            duration: 100,
            exactProgress: 5,
            isPlaying: true,
            now: start.addingTimeInterval(2.4)
        )
        XCTAssertEqual(confirmedBackwardSeek, 5, accuracy: 0.001)
    }

    func testNetEaseIgnoresOneOffStaleBackwardLevelDBRecord() {
        var estimator = NetEaseProgressEstimator()
        let start = Date(timeIntervalSince1970: 10_000)
        _ = estimator.update(songID: "1", duration: 100, exactProgress: 20, isPlaying: true, now: start)
        let beforeStaleRecord = estimator.update(
            songID: "1",
            duration: 100,
            exactProgress: 20,
            isPlaying: true,
            now: start.addingTimeInterval(0.8)
        )
        let staleRecord = estimator.update(
            songID: "1",
            duration: 100,
            exactProgress: 4,
            isPlaying: true,
            now: start.addingTimeInterval(0.81)
        )
        let recoveredNativeValue = estimator.update(
            songID: "1",
            duration: 100,
            exactProgress: 21,
            isPlaying: true,
            now: start.addingTimeInterval(1)
        )

        XCTAssertGreaterThanOrEqual(staleRecord, beforeStaleRecord)
        XCTAssertGreaterThanOrEqual(recoveredNativeValue, staleRecord)
    }

    func testNetEaseAcceptsPausedBackwardSeekImmediately() {
        var estimator = NetEaseProgressEstimator()
        let start = Date(timeIntervalSince1970: 10_000)
        _ = estimator.update(songID: "1", duration: 100, exactProgress: 20, isPlaying: true, now: start)
        XCTAssertEqual(
            estimator.update(
                songID: "1",
                duration: 100,
                exactProgress: 4,
                isPlaying: false,
                now: start.addingTimeInterval(0.5)
            ),
            4,
            accuracy: 0.001
        )
    }

    func testNetEasePauseDoesNotRewindToDelayedNativeWrite() {
        var estimator = NetEaseProgressEstimator()
        let start = Date(timeIntervalSince1970: 10_000)
        _ = estimator.update(songID: "1", duration: 100, exactProgress: 10, isPlaying: true, now: start)
        let interpolated = estimator.update(
            songID: "1",
            duration: 100,
            exactProgress: 10,
            isPlaying: true,
            now: start.addingTimeInterval(3)
        )
        let stoppedWithStaleValue = estimator.update(
            songID: "1",
            duration: 100,
            exactProgress: 10,
            isPlaying: false,
            now: start.addingTimeInterval(3.1)
        )
        let delayedPausedWrite = estimator.update(
            songID: "1",
            duration: 100,
            exactProgress: 11,
            isPlaying: false,
            now: start.addingTimeInterval(3.2)
        )

        XCTAssertEqual(interpolated, 13, accuracy: 0.001)
        XCTAssertEqual(stoppedWithStaleValue, interpolated, accuracy: 0.001)
        XCTAssertEqual(delayedPausedWrite, interpolated, accuracy: 0.001)
    }

    func testNetEaseInterpolationClampsAtTrackEndUntilNativeTrackChange() {
        var estimator = NetEaseProgressEstimator()
        let start = Date(timeIntervalSince1970: 10_000)
        _ = estimator.update(songID: "1", duration: 10, exactProgress: 9, isPlaying: true, now: start)
        XCTAssertEqual(
            estimator.update(songID: "1", duration: 10, exactProgress: 9, isPlaying: true, now: start.addingTimeInterval(2)),
            10,
            accuracy: 0.001
        )
    }

    func testNetEasePlaybackActivityPrefersCoreAudioAndUsesStaleFallback() {
        var resolver = NetEasePlaybackActivityResolver()
        let start = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(resolver.resolve(songID: "1", exactProgress: 10, audible: true, now: start))
        XCTAssertTrue(resolver.resolve(songID: "1", exactProgress: 10, audible: true, now: start.addingTimeInterval(20)))
        XCTAssertTrue(resolver.resolve(songID: "1", exactProgress: 11, audible: nil, now: start.addingTimeInterval(20.1)))
        XCTAssertFalse(resolver.resolve(songID: "1", exactProgress: 11, audible: nil, now: start.addingTimeInterval(26.7)))
        XCTAssertFalse(resolver.resolve(songID: "1", exactProgress: 11, audible: false, now: start.addingTimeInterval(26.8)))
    }

    func testDelayedNativeTickIncludesTimeSincePreviousObservation() {
        var estimator = NetEaseProgressEstimator()
        let start = Date(timeIntervalSince1970: 10_000)
        _ = estimator.update(songID: "1", duration: 100, exactProgress: 10, isPlaying: true, now: start)
        _ = estimator.update(songID: "1", duration: 100, exactProgress: 10, isPlaying: true, now: start.addingTimeInterval(1.4))
        let next = estimator.update(songID: "1", duration: 100, exactProgress: 11, isPlaying: true, now: start.addingTimeInterval(1.6))
        XCTAssertEqual(next, 11.6, accuracy: 0.001)
    }

    func testNextLyricDeadlineIncludesDocumentOffsetAndPrelude() {
        let document = LyricsDocument(track: .init(title: "t", artist: "a"), lines: [
            .init(time: 3, text: "one"), .init(time: 7, text: "two")
        ], source: "test", offset: 0.5)
        XCTAssertNil(document.lineIndex(at: 3.49))
        XCTAssertEqual(document.nextLineDelay(after: 1), 2.5)
        XCTAssertEqual(document.nextLineDelay(after: 3.5), 4)
        XCTAssertNil(document.nextLineDelay(after: 7.5))
    }

    func testRefreshModesAndLowPowerPolicy() {
        XCTAssertEqual(RefreshMode.balanced.pollingInterval(lowPower: false), 0.5)
        XCTAssertEqual(RefreshMode.balanced.pollingInterval(lowPower: true), 1)
        XCTAssertEqual(RefreshMode.responsive.pollingInterval(lowPower: true), 0.2)
        XCTAssertEqual(RefreshMode.energySaving.pollingInterval(lowPower: false), 1)
    }

    func testNetEasePermissionDenialIsActionableInsteadOfWaiting() {
        for error in [NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
                      NSError(domain: NSPOSIXErrorDomain, code: 1),
                      NSError(domain: NSPOSIXErrorDomain, code: 13)] {
            let message = NetEaseLocalReadFailure.message(for: error)
            XCTAssertTrue(message?.contains("完全磁盘访问权限") == true)
            XCTAssertTrue(message?.contains("辅助功能授权不包含此权限") == true)
        }
        XCTAssertNil(NetEaseLocalReadFailure.message(for: NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)))
        XCTAssertTrue(NetEaseLocalReadFailure.message(for: NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError))?.contains("读取失败") == true)
    }

    private func lyrics(_ lines: [TimedLyricLine]) -> LyricsDocument {
        .init(track: .init(title: "t", artist: "a"), lines: lines, source: "test")
    }
}
