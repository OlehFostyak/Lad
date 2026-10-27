import AppKit
import ApplicationServices

/// The Accessibility permission Lad needs to see key presses and retype words.
enum Permissions {
    private static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// The system prompt that leads to System Settings › Privacy & Security › Accessibility.
    /// (The option key is spelled out: the imported constant is a mutable global in Swift 6.)
    static func requestTrust() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
