import Foundation
import Observation

@MainActor @Observable
final class SettingsController {
    private(set) var value = AppPreferences()
    private(set) var isLoaded: Bool
    private(set) var isSaving = false
    // 只记住本次运行的分页，不将窗口导航状态写入用户偏好。
    var selectedTab: SettingsTab = .playback
    var errorMessage: String?
    @ObservationIgnored private let store: LibraryStore?
    @ObservationIgnored private let playback: PlaybackController
    @ObservationIgnored private var isLoading = false

    init(store: LibraryStore?, playback: PlaybackController) {
        self.store = store
        self.playback = playback
        isLoaded = store == nil
    }

    static func preview() -> SettingsController {
        let controller = SettingsController(store: nil, playback: PlaybackController(connectSystemMedia: false))
        controller.value = AppPreferences(crossfadeEnabled: true)
        return controller
    }

    func load() async {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let restored = try await store?.preferences() ?? AppPreferences()
            try Task.checkCancellation()
            apply(restored, atStartup: true)
            isLoaded = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "无法读取设置：\(error.localizedDescription)"
        }
    }

    func save(_ draft: AppPreferences) async -> Bool {
        guard isLoaded, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let normalized = draft.normalized
            try await store?.savePreferences(normalized)
            apply(normalized, atStartup: false)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "无法保存设置：\(error.localizedDescription)"
            return false
        }
    }

    private func apply(_ preferences: AppPreferences, atStartup: Bool) {
        let previous = value
        value = preferences.normalized
        playback.configureCrossfade(enabled: value.crossfadeEnabled, duration: value.crossfadeDuration)
        if atStartup || previous.defaultPlaybackMode != value.defaultPlaybackMode {
            playback.mode = value.defaultPlaybackMode
        }
        if atStartup { playback.volume = value.startupVolume }
    }
}
