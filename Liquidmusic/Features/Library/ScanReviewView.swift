import SwiftUI

struct ScanReviewView: View {
    let plan: LibraryScanPlan
    var onApply: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认资料库变更").font(.title2).bold()
            Text("「\(plan.folder.displayName)」将新增 \(plan.additions.count) 首、更新 \(plan.updates.count) 首，并移除 \(plan.missing.count) 条失踪索引。")
            Text("仅修改资料库索引，不会移动、覆盖或删除本地音频文件。取消将保留现有索引。")
                .font(.callout).foregroundStyle(.secondary)
            // 显式容器稳定每行的视图数量，规避 macOS Preview 对自定义列表行的崩溃。
            List(entries) { entry in ZStack(alignment: .leading) { reviewRow(entry) } }
            if !plan.enumerationComplete {
                Label("部分目录未能读取，本次不会清理失踪索引。", systemImage: "exclamationmark.triangle")
                    .font(.callout)
            }
            if !plan.issues.isEmpty {
                Text("另有 \(plan.issues.count) 个问题，应用变更后可查看完整报告。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("取消", role: .cancel, action: onCancel)
                Spacer()
                Button("应用索引变更", action: onApply).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(minWidth: 580, minHeight: 440)
        .interactiveDismissDisabled()
    }

    private var entries: [ReviewEntry] {
        plan.changes.map { ReviewEntry(track: $0, previous: plan.baseline[$0.path], removed: false) }
            + plan.missing.map { ReviewEntry(track: $0, previous: nil, removed: true) }
    }

    private func reviewRow(_ entry: ReviewEntry) -> some View {
        let track = entry.track
        return VStack(alignment: .leading, spacing: 4) {
            Text(entry.removed ? "移除失踪索引" : entry.previous == nil ? "新增" : "更新现有索引")
                .font(.caption).foregroundStyle(.secondary)
            Text(track.title).font(.headline)
            if let old = entry.previous {
                if old.title != track.title { Text("标题：\(old.title) → \(track.title)") }
                if old.artist != track.artist { Text("艺术家：\(old.artist) → \(track.artist)") }
                if old.album != track.album { Text("专辑：\(old.album) → \(track.album)") }
                if old.albumArtist != track.albumArtist { Text("专辑艺术家：\(old.albumArtist) → \(track.albumArtist)") }
                if old.trackNumber != track.trackNumber || old.discNumber != track.discNumber {
                    Text("碟号/曲号：\(old.discNumber)/\(old.trackNumber) → \(track.discNumber)/\(track.trackNumber)")
                }
                if old.duration != track.duration { Text("时长：\(old.durationText) → \(track.durationText)") }
                if old.artworkPath != track.artworkPath { Text("封面将更新") }
                if old.folderID != track.folderID { Text("所属文件夹将更新为「\(plan.folder.displayName)」") }
                Text("将刷新文件大小与修改时间").font(.caption).foregroundStyle(.secondary)
            }
            Text(track.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }.font(.callout).padding(.vertical, 4)
    }

    private struct ReviewEntry: Identifiable {
        let track: Track
        let previous: Track?
        let removed: Bool
        var id: String { "\(removed ? "remove" : "save"):\(track.path)" }
    }
}

private enum ScanReviewPreviewData {
    static var plan: LibraryScanPlan {
        let old = SPXData.tracks[0]
        var updated = old
        updated.title = "夜航（新版）"
        updated.album = "蓝色时刻 · 重制版"
        let missing = SPXData.tracks[2]
        return LibraryScanPlan(id: UUID(), folder: LibraryFolder(path: "/preview", displayName: "我的音乐", bookmarkData: Data()),
                               rootURL: URL(fileURLWithPath: "/preview"), baseline: [old.path: old, missing.path: missing],
                               changes: [updated, SPXData.tracks[1]], missing: [missing],
                               reused: 0, skipped: 0, enumerationComplete: true, issues: [], scannedAt: .now)
    }
}

#Preview { ScanReviewView(plan: ScanReviewPreviewData.plan, onApply: {}, onCancel: {}) }
