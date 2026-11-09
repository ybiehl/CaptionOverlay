import AppKit
import CaptionCore
import SwiftUI

// CaptionPanel: the caption bar. A borderless panel that floats over every
// app and Space, including other apps' full-screen windows, and never
// takes the keyboard. Drag it anywhere; drag its left or right edge to
// change the width. Its place is remembered.

@MainActor
final class CaptionPanel: NSObject, NSWindowDelegate {
    private enum Layout {
        static let font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        static let lineCount = 2
        static let padding: CGFloat = 18
        static let lineHeight = ceil(font.ascender - font.descender + font.leading) + 4
        static let height = lineHeight * CGFloat(lineCount) + padding * 2
        static let minWidth: CGFloat = 320
        /// Share of the screen's width on first start.
        static let firstWidth: CGFloat = 0.6
        /// Gap to the bottom of the screen on first start.
        static let firstBottom: CGFloat = 90
        /// The bar empties when no new words came for this long.
        static let emptyAfter: TimeInterval = 4
    }

    private static let frameKey = "app.captionoverlay.barFrame"

    private final class Model: ObservableObject {
        @Published var lines: [String] = []
    }

    private struct BarView: View {
        @ObservedObject var model: Model

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Text sits on the bottom line first; a second line pushes
                // the first one up.
                Spacer(minLength: 0)
                ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(Font(Layout.font))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(height: Layout.lineHeight, alignment: .leading)
                }
            }
            .padding(Layout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private let model = Model()
    private var text = CaptionText(lineCount: Layout.lineCount)
    private var panel: NSPanel?
    private var emptyTimer: Timer?

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        text.clear()
        model.lines = []
        panel.orderFrontRegardless()
    }

    func hide() {
        emptyTimer?.invalidate()
        emptyTimer = nil
        panel?.orderOut(nil)
    }

    func apply(_ update: CaptionUpdate) {
        text.apply(update)
        layout()
        emptyTimer?.invalidate()
        emptyTimer = Timer.scheduledTimer(
            withTimeInterval: Layout.emptyAfter, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.text.clear()
                self?.model.lines = []
            }
        }
    }

    private func layout() {
        guard let panel else { return }
        let width = panel.frame.width - Layout.padding * 2
        let attributes: [NSAttributedString.Key: Any] = [.font: Layout.font]
        model.lines = text.lines { line in
            (line as NSString).size(withAttributes: attributes).width <= width
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: savedFrame() ?? firstFrame(),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: Layout.minWidth, height: Layout.height)
        panel.maxSize = NSSize(width: 10000, height: Layout.height)
        panel.contentView = NSHostingView(rootView: BarView(model: model))
        panel.delegate = self
        return panel
    }

    private func firstFrame() -> NSRect {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = max(Layout.minWidth, screen.width * Layout.firstWidth)
        return NSRect(x: screen.midX - width / 2, y: screen.minY + Layout.firstBottom,
                      width: width, height: Layout.height)
    }

    /// The remembered place, unless the screen it was on is gone.
    private func savedFrame() -> NSRect? {
        guard let saved = UserDefaults.standard.string(forKey: Self.frameKey) else { return nil }
        var frame = NSRectFromString(saved)
        frame.size.height = Layout.height
        guard frame.width >= Layout.minWidth,
              NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) })
        else { return nil }
        return frame
    }

    private func saveFrame() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
        layout()
    }
}
