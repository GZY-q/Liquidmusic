import SwiftUI

struct AudioImportNotice: View {
    let warnings: [String]
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("打开音频的提示", systemImage: "info.circle").font(.callout)
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, message in
                    Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            Button("关闭提示", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("关闭音频提示")
        }.padding().background(.bar)
    }
}

#Preview("封面失败仍可播放") {
    AudioImportNotice(warnings: ["封面图片损坏，已使用默认封面。"])
        .frame(width: 400)
}
