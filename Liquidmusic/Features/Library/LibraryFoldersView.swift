import SwiftUI

struct LibraryFoldersView: View {
    @Bindable var controller: LibraryController
    @Environment(\.dismiss) private var dismiss
    @State private var showsReport = false

    var body: some View {
        Group {
            if let plan = controller.pendingReview {
                ScanReviewView(plan: plan, onApply: controller.applyReviewedChanges, onCancel: controller.cancelScan)
            } else { content }
        }
        .sheet(isPresented: $showsReport) { ImportReportView(reports: controller.scanReports) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("音乐文件夹").font(.title2).bold()
                    Text("管理已保存的文件夹访问权限。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(controller.scanProgress?.phase == .saving)
            }.padding(20)
            Divider()
            if let progress = controller.scanProgress {
                ImportProgressView(progress: progress, reports: controller.scanReports,
                                   onCancel: controller.cancelScan, onReview: {}, onReport: { showsReport = true })
            }
            switch controller.state {
            case .idle, .loading:
                ProgressView("正在打开资料库…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("资料库暂不可用", systemImage: "externaldrive.badge.exclamationmark")
                } description: { Text(message) } actions: {
                    Button("重试", action: controller.start)
                }
            case .ready:
                if controller.folders.isEmpty {
                    ContentUnavailableView("尚未添加文件夹", systemImage: "folder.badge.plus", description: Text("选择本地音乐文件夹，保存下次启动时的访问权限。"))
                } else {
                    List(controller.folders) { snapshot in
                        HStack(spacing: 12) {
                            Image(systemName: snapshot.status.isAvailable ? "folder.fill" : "folder.badge.questionmark")
                                .font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.folder.displayName).font(.headline)
                                Text(snapshot.folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                                Text(snapshot.status.message).font(.caption)
                                    .foregroundStyle(snapshot.status.isAvailable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                            }
                            Spacer()
                            if !snapshot.status.isAvailable {
                                Button("重新授权…") { controller.chooseFolder(replacing: snapshot.folder) }
                                    .disabled(controller.isBusy)
                            } else {
                                Button("扫描") { controller.startScan(folderIDs: [snapshot.id]) }
                                    .disabled(controller.isBusy)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Button("添加音乐文件夹…", systemImage: "folder.badge.plus") { controller.chooseFolder() }
                    .disabled(controller.state != .ready || controller.isBusy)
                Button("扫描所有文件夹") { controller.startScan() }
                    .disabled(controller.state != .ready || controller.isBusy || controller.folders.isEmpty)
                if controller.isWorking { ProgressView().controlSize(.small) }
                Spacer()
            }.padding(20)
        }
        .frame(minWidth: 540, idealWidth: 600, minHeight: 360, idealHeight: 440)
        .alert("资料库操作失败", isPresented: Binding(get: { controller.operationError != nil }, set: { if !$0 { controller.operationError = nil } })) {
            Button("好", role: .cancel) { controller.operationError = nil }
        } message: { Text(controller.operationError ?? "") }
    }
}

#Preview { LibraryFoldersView(controller: .preview()) }
