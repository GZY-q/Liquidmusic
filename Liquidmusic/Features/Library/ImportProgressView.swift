import SwiftUI

struct ImportProgressView: View {
    let progress: ScanProgress
    let reports: [ScanReport]
    var onCancel: () -> Void
    var onReview: () -> Void
    var onReport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if progress.phase == .discovering || progress.phase == .indexing || progress.phase == .saving {
                ProgressView().controlSize(.small)
            } else { Image(systemName: progress.phase == .failed ? "exclamationmark.triangle" : "music.note.list") }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout)
                if progress.phase == .indexing {
                    ProgressView(value: Double(progress.processed), total: Double(max(progress.total, 1)))
                        .accessibilityLabel("索引进度")
                    Text(progress.currentFile ?? progress.folderName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            switch progress.phase {
            case .discovering, .indexing:
                Button("取消", action: onCancel)
            case .reviewing:
                Button("查看变更…", action: onReview)
            case .finished, .failed, .cancelled:
                if !reports.isEmpty { Button("查看报告…", action: onReport) }
            case .saving: EmptyView()
            }
        }.padding().background(.bar)
    }

    private var title: String {
        switch progress.phase {
        case .discovering: "正在查找「\(progress.folderName)」· 已发现 \(progress.discovered) 首"
        case .indexing: "正在索引「\(progress.folderName)」· \(progress.processed)/\(progress.total)"
        case .reviewing: "扫描完成，已有索引变更等待确认"
        case .saving: "正在保存「\(progress.folderName)」"
        case .finished: "\(reports.allSatisfy(\.enumerationComplete) ? "扫描完成" : "部分完成") · 新增 \(reports.reduce(0) { $0 + $1.added }) 首，跳过 \(reports.reduce(0) { $0 + $1.skipped }) 首，\(reports.reduce(0) { $0 + $1.issues.count }) 个问题"
        case .cancelled: "扫描已取消"
        case .failed: "扫描未完成"
        }
    }
}

struct ImportReportView: View {
    let reports: [ScanReport]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("导入报告").font(.title2).bold()
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            List(reports) { report in
                Section(report.folderName) {
                    Text("新增 \(report.added) · 更新 \(report.updated) · 未变化 \(report.reused) · 跳过 \(report.skipped) · 清理索引 \(report.removed)")
                        .font(.callout)
                    if !report.enumerationComplete {
                        Label("部分目录读取失败，未清理失踪索引。", systemImage: "exclamationmark.triangle")
                    }
                    ForEach(report.issues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.reason)
                            Text(issue.filePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }.padding(.vertical, 4)
                    }
                    if report.issues.isEmpty { Text("未发现问题").foregroundStyle(.secondary) }
                }
            }
        }.padding(20).frame(minWidth: 560, minHeight: 380)
    }
}

#Preview { ImportProgressView(progress: ScanProgress(phase: .indexing, folderName: "我的音乐", processed: 12, total: 30), reports: [], onCancel: {}, onReview: {}, onReport: {}) }
#Preview("报告") {
    ImportReportView(reports: [ScanReport(id: UUID(), folderName: "我的音乐", added: 12, updated: 1, reused: 23,
                                         skipped: 1, removed: 0, enumerationComplete: false,
                                         issues: [ImportIssue(folderID: "preview", filePath: "/preview/broken.flac", reason: "已跳过无法解码的音频")])])
}
