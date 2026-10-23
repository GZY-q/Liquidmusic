import AppKit
import SwiftUI

// 独立空白带只负责移动窗口，不覆盖工具栏、列表或侧边栏的交互区域。
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            // 系统将辅助功能的三指拖移转换为拖动事件，无需全局手势监听。
            window?.performDrag(with: event)
        }
    }
}

#Preview { WindowDragArea().frame(width: 640, height: 24) }
