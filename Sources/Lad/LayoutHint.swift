import AppKit
import ApplicationServices
import SwiftUI

/// A small "UA" / "EN" badge that flashes next to the text caret (or the mouse, when the app does
/// not tell where its caret is) after Lad switches the layout. It never takes focus or clicks.
final class LayoutHint {
    private static let visibleFor: Duration = .milliseconds(800)
    private static let fadeDuration: TimeInterval = 0.2
    private static let gap: CGFloat = 4

    private let panel: NSPanel
    private let content = HintContent()
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 22), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: HintBadge(content: content))
    }

    /// Shows `text`, yellow and blue for Ukrainian, dark otherwise.
    func show(_ text: String, ukrainian: Bool) {
        content.text = text
        content.isUkrainian = ukrainian
        let size = panel.contentView?.fittingSize ?? NSSize(width: 40, height: 22)
        panel.setFrame(NSRect(origin: Self.origin(for: size), size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeDuration))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    /// Below the caret, else below and right of the mouse pointer.
    private static func origin(for size: NSSize) -> NSPoint {
        if let caret = caretRect() {
            return NSPoint(x: caret.minX, y: caret.minY - size.height - gap)
        }
        let mouse = NSEvent.mouseLocation
        return NSPoint(x: mouse.x + 3 * gap, y: mouse.y - size.height - 3 * gap)
    }

    /// The caret of the focused text, in AppKit screen coordinates, from Accessibility.
    private static func caretRect() -> NSRect? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0,
              let primary = NSScreen.screens.first else { return nil }
        // Accessibility measures from the top left of the primary screen, AppKit from its bottom left.
        return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

private final class HintContent: ObservableObject {
    @Published var text = ""
    @Published var isUkrainian = false
}

private struct HintBadge: View {
    private static let blue = Color(red: 0, green: 0.34, blue: 0.72)
    private static let yellow = Color(red: 1, green: 0.84, blue: 0)

    @ObservedObject var content: HintContent

    var body: some View {
        Text(content.text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(content.isUkrainian ? Self.blue : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(content.isUkrainian ? Self.yellow : Color.black.opacity(0.78)))
            .fixedSize()
    }
}
