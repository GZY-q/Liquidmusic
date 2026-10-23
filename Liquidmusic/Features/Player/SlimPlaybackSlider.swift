import SwiftUI

// 使用系统 Slider 呈现当前 macOS 的轨道与液态玻璃旋钮。
struct SlimPlaybackSlider: View {
    @Binding var value: Double
    var maximum: Double
    var isEnabled: Bool
    var onEditingChanged: (Bool) -> Void
    var controlSize: ControlSize = .mini
    @FocusState private var isFocused: Bool

    var body: some View {
        Slider(value: $value, in: 0...max(maximum, 1), onEditingChanged: onEditingChanged)
            .controlSize(controlSize)
            .focusable().focused($isFocused)
            .simultaneousGesture(TapGesture().onEnded { isFocused = true })
            .onKeyPress(.leftArrow) { move(by: -5) }
            .onKeyPress(.rightArrow) { move(by: 5) }
            .accessibilityLabel("播放进度")
            .accessibilityValue(Track.timeText(value))
            .help("已播放 \(Track.timeText(value))，共 \(Track.timeText(maximum))；左右方向键跳转 5 秒")
            .disabled(!isEnabled)
    }

    private func move(by offset: Double) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        value = min(maximum, max(0, value + offset))
        return .handled
    }
}

#Preview {
    SlimPlaybackSlider(value: .constant(35), maximum: 120, isEnabled: true, onEditingChanged: { _ in })
        .frame(width: 320, height: 18).padding()
}
