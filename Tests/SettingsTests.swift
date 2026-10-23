import XCTest
@testable import Liquidmusic

@MainActor
final class SettingsTests: XCTestCase {
    func testPreferencesSurviveReopenWithoutChangingLibrary() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("Settings.sqlite")
        let store = LibraryStore(location: .file(url))
        let folder = try await store.saveFolder(fixture.folder())
        let tracks = try await store.upsertTracks([fixture.track(folderID: folder.id)])
        let defaults = try await store.preferences()
        XCTAssertEqual(defaults, AppPreferences())
        let expected = AppPreferences(appearance: .dark, showsMenuBarPlayer: false, crossfadeEnabled: true,
                                      crossfadeDuration: 12, defaultPlaybackMode: .shuffle, startupVolume: 0.2)
        try await store.savePreferences(expected)
        try await store.close()
        let reopened = LibraryStore(location: .file(url))
        let actual = try await reopened.preferences()
        let retained = try await reopened.tracks()
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(retained, tracks)
        try await reopened.close()
    }

    func testDraftDoesNotApplyUntilSavedAndStartupRestoresPlaybackPreferences() async throws {
        let store = LibraryStore(location: .memory)
        let playback = PlaybackController(connectSystemMedia: false)
        defer { playback.shutdown() }
        let controller = SettingsController(store: store, playback: playback)
        await controller.load()
        var draft = controller.value
        draft.crossfadeEnabled = true
        draft.crossfadeDuration = 9
        draft.defaultPlaybackMode = .repeatAll
        draft.startupVolume = 0.25
        XCTAssertFalse(playback.crossfadeEnabled)
        XCTAssertEqual(controller.value, AppPreferences())
        let saved = await controller.save(draft)
        XCTAssertTrue(saved)
        XCTAssertTrue(playback.crossfadeEnabled)
        XCTAssertEqual(playback.crossfadeDuration, 9)
        XCTAssertEqual(playback.mode, .repeatAll)
        XCTAssertEqual(playback.volume, 0.7)
        // 外观等无关更改不得覆盖用户在播放条中临时选择的模式。
        playback.mode = .shuffle
        draft.appearance = .dark
        let savedAppearance = await controller.save(draft)
        XCTAssertTrue(savedAppearance)
        XCTAssertEqual(playback.mode, .shuffle)
        let restored = SettingsController(store: store, playback: playback)
        await restored.load()
        XCTAssertEqual(playback.volume, 0.25)
        XCTAssertEqual(playback.mode, .repeatAll)
        XCTAssertEqual(playback.status, .idle)
    }

    func testInvalidValuesAreNormalizedBeforePersistence() async throws {
        let store = LibraryStore(location: .memory)
        var value = AppPreferences()
        value.crossfadeDuration = .nan
        value.startupVolume = .infinity
        try await store.savePreferences(value)
        let normalized = try await store.preferences()
        XCTAssertEqual(normalized.crossfadeDuration, 6)
        XCTAssertEqual(normalized.startupVolume, 0.7)
        value.crossfadeDuration = 99
        value.startupVolume = -2
        XCTAssertEqual(value.normalized.crossfadeDuration, 12)
        XCTAssertEqual(value.normalized.startupVolume, 0)
    }

    func testReadFailureDoesNotPretendSettingsWereSaved() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let blocker = fixture.root.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let playback = PlaybackController(connectSystemMedia: false)
        defer { playback.shutdown() }
        let controller = SettingsController(store: LibraryStore(location: .file(blocker.appendingPathComponent("db"))), playback: playback)
        await controller.load()
        XCTAssertFalse(controller.isLoaded)
        XCTAssertNotNil(controller.errorMessage)
        let saved = await controller.save(AppPreferences(crossfadeEnabled: true))
        XCTAssertFalse(saved)
        XCTAssertFalse(playback.crossfadeEnabled)
    }

    func testEnvelopeClampsAndShortTracksLimitOverlap() {
        let envelope = CrossfadeEnvelope(duration: 4)
        XCTAssertEqual(envelope.gains(at: -1).incoming, 0)
        XCTAssertEqual(envelope.gains(at: 2).incoming, 0.5)
        XCTAssertEqual(envelope.gains(at: 2).outgoing, 0.5)
        XCTAssertEqual(envelope.gains(at: 6).outgoing, 0)
        XCTAssertEqual(CrossfadeEnvelope.duration(requested: 12, outgoing: 4, incoming: 2), 1)
        XCTAssertEqual(CrossfadeEnvelope.duration(requested: 6, outgoing: .nan, incoming: 8), 0)
    }
}
