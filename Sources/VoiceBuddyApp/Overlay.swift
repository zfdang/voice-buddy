import AppKit
import SwiftUI

@MainActor final class Overlay {
    private var panel: NSPanel?
    func show(state: AppState) {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 58), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true; panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: OverlayView(state: state))
            self.panel = panel
        }
        if let screen = NSScreen.main, let panel { let frame = screen.visibleFrame; panel.setFrameOrigin(NSPoint(x: frame.midX - 130, y: frame.minY + 40)); panel.orderFrontRegardless() }
    }
    func hide() { panel?.orderOut(nil) }
}

private struct OverlayView: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill").foregroundStyle(.green)
            VStack(alignment: .leading) { Text(state.recording ? state.label("Listening…", "正在听你说…") : state.status).font(.caption.bold()); if state.recording { ProgressView(value: min(Double(state.level) * 12, 1)).frame(width: 120) } }
            Spacer()
            if state.recording { Button("×") { state.cancel() }.buttonStyle(.plain).accessibilityLabel(state.label("Cancel", "取消")) }
        }.padding(12).frame(width: 260, height: 58).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
