import AppKit
import ApplicationServices

/// Reports when the keyboard focus moves inside the front app (a dialog, another field, a web page
/// moving focus), which clicks and app switches do not cover. Lad must then forget the word: its
/// Backspaces would land in the new field.
final class FocusObserver {
    /// Accessibility calls run on the main thread, which also runs the event tap: a hung app must
    /// not stall typing for the multi-second default.
    static let messagingTimeout: Float = 0.25
    /// An app that is still launching may refuse the observer; Lad tries once more after this.
    private static let retryDelay: Duration = .seconds(1)

    var onFocusChange: (() -> Void)?

    private var observer: AXObserver?
    private var application: AXUIElement?
    private var retry: Task<Void, Never>?

    /// Caps every Accessibility call Lad makes (the system-wide element sets the default for all).
    static func limitAccessibilityTimeouts() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }

    /// Watches the app with this process ID instead of the previous one; needs the Accessibility permission.
    func observe(processID: pid_t?) {
        stop()
        guard let processID, Permissions.isTrusted, !attach(to: processID) else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            guard let self, !Task.isCancelled, observer == nil,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return }
            _ = attach(to: processID)
        }
    }

    func stop() {
        retry?.cancel()
        retry = nil
        if let observer, let application {
            AXObserverRemoveNotification(observer, application, kAXFocusedUIElementChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        application = nil
    }

    private func attach(to processID: pid_t) -> Bool {
        var created: AXObserver?
        guard AXObserverCreate(processID, focusCallback, &created) == .success, let created else { return false }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(created, application, kAXFocusedUIElementChangedNotification as CFString, refcon) == .success else {
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        self.application = application
        return true
    }

    fileprivate func focusDidChange() {
        onFocusChange?()
    }
}

/// The AX callback runs on the main run loop, where the observer's source was added.
private nonisolated func focusCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let focus = Unmanaged<FocusObserver>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { focus.focusDidChange() }
}
