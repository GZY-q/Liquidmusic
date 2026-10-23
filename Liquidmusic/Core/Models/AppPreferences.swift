import Foundation

enum AppAppearance: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var appearance: AppAppearance = .system
    var showsMenuBarPlayer = true
    var crossfadeEnabled = false
    var crossfadeDuration: Double = 6
    var defaultPlaybackMode: PlaybackMode = .sequential
    var startupVolume: Double = 0.7

    var normalized: Self {
        var result = self
        result.crossfadeDuration = crossfadeDuration.isFinite ? min(12, max(1, crossfadeDuration.rounded())) : 6
        result.startupVolume = startupVolume.isFinite ? min(1, max(0, startupVolume)) : 0.7
        return result
    }
}

// 线性互补增益避免重叠时两路同时以完整音量输出。
struct CrossfadeEnvelope: Equatable, Sendable {
    let duration: Double

    func gains(at elapsed: Double) -> (incoming: Double, outgoing: Double) {
        let progress = duration > 0 && elapsed.isFinite ? min(1, max(0, elapsed / duration)) : 1
        return (progress, 1 - progress)
    }

    static func duration(requested: Double, outgoing: Double, incoming: Double) -> Double {
        guard requested.isFinite, outgoing.isFinite, incoming.isFinite,
              requested > 0, outgoing > 0, incoming > 0 else { return 0 }
        // 短曲最多重叠一半，保证每个条目有独立播放区间。
        return min(requested, outgoing / 2, incoming / 2)
    }
}
