import AppKit
import LadCore
import SwiftUI

/// The menu bar icon; a click opens the settings popover.
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let controller: TypingController
    private let settings: Settings
    private let model: PanelModel

    init(controller: TypingController, settings: Settings, model: PanelModel) {
        self.controller = controller
        self.settings = settings
        self.model = model
        super.init()
        let hosting = NSHostingController(rootView: PanelView(model: model))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Lad"
        }
        refresh()
    }

    var isPanelShown: Bool { popover.isShown }

    func showPanel() {
        guard let button = item.button, !popover.isShown else { return }
        model.refresh()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// The icon: the chosen style; dimmed while paused or manual-only; a warning when Lad cannot work.
    func refresh() {
        guard let button = item.button else { return }
        let needsAttention = !controller.isTapRunning || controller.layouts == nil || controller.dictionaries == .failed
        button.appearsDisabled = !needsAttention && (controller.isPausedInFrontApp || !controller.isAutomatic)
        if needsAttention {
            show(NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Lad: потрібна увага"), on: button)
            return
        }
        switch settings.iconStyle {
        case .keyboard:
            show(NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Lad"), on: button)
        case .glyph:
            show(Self.glyph, on: button)
        case .layout:
            button.image = nil
            button.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            button.title = controller.layouts?.current.language == .ukrainian ? "UA" : "EN"
        }
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    private func show(_ image: NSImage?, on button: NSStatusBarButton) {
        button.title = ""
        image?.isTemplate = true
        button.image = image
    }

    /// A keycap with Л, drawn as a template image at 2×.
    private static let glyph = makeGlyph()

    private static func makeGlyph() -> NSImage {
        let points = NSSize(width: 18, height: 16)
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(points.width * scale), pixelsHigh: Int(points.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return NSImage() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        let cap = NSBezierPath(roundedRect: NSRect(origin: .zero, size: points).insetBy(dx: 1, dy: 1), xRadius: 3.5, yRadius: 3.5)
        cap.lineWidth = 1.4
        NSColor.black.setStroke()
        cap.stroke()
        let legend = NSAttributedString(
            string: "Л", attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .bold), .foregroundColor: NSColor.black]
        )
        let size = legend.size()
        legend.draw(at: NSPoint(x: (points.width - size.width) / 2, y: (points.height - size.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = points
        let image = NSImage(size: points)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }
}
