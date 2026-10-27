import Foundation
import ServiceManagement

/// How the menu bar icon looks.
enum IconStyle: String, CaseIterable, Identifiable {
    /// A keyboard symbol.
    case keyboard
    /// A keycap with Л, like the app icon.
    case glyph
    /// The current layout: EN or UA.
    case layout

    var id: String { rawValue }
}

/// Lad's preferences in UserDefaults: switches and the words the user turned back after an
/// automatic conversion. Nothing else that was typed is ever stored.
final class Settings {
    private enum Key {
        static let automatic = "automaticSwitching"
        static let convertsOnReturn = "convertsOnReturn"
        static let exceptions = "exceptions"
        static let playsSound = "playsSound"
        static let iconStyle = "iconStyle"
        static let didFirstLaunchSetup = "didFirstLaunchSetup"
        /// Per-app pause, removed in 0.1.1; its list is dropped on launch.
        static let removedExcludedApps = "excludedApps"
    }

    /// The longest exception list kept; the oldest words go first.
    static let maxExceptions = 500

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.automatic: true, Key.convertsOnReturn: true, Key.iconStyle: IconStyle.keyboard.rawValue,
        ])
        defaults.removeObject(forKey: Key.removedExcludedApps)
    }

    var isAutomatic: Bool {
        get { defaults.bool(forKey: Key.automatic) }
        set { defaults.set(newValue, forKey: Key.automatic) }
    }

    var convertsOnReturn: Bool {
        get { defaults.bool(forKey: Key.convertsOnReturn) }
        set { defaults.set(newValue, forKey: Key.convertsOnReturn) }
    }

    var playsSound: Bool {
        get { defaults.bool(forKey: Key.playsSound) }
        set { defaults.set(newValue, forKey: Key.playsSound) }
    }

    var iconStyle: IconStyle {
        get { defaults.string(forKey: Key.iconStyle).flatMap(IconStyle.init(rawValue:)) ?? .keyboard }
        set { defaults.set(newValue.rawValue, forKey: Key.iconStyle) }
    }

    /// Set once the first launch turned on the login item and showed the panel.
    var didFirstLaunchSetup: Bool {
        get { defaults.bool(forKey: Key.didFirstLaunchSetup) }
        set { defaults.set(newValue, forKey: Key.didFirstLaunchSetup) }
    }

    /// Oldest first.
    var exceptions: [String] {
        defaults.stringArray(forKey: Key.exceptions) ?? []
    }

    func addException(_ word: String) {
        var list = exceptions.filter { $0 != word }
        list.append(word)
        defaults.set(Array(list.suffix(Self.maxExceptions)), forKey: Key.exceptions)
    }

    func removeException(_ word: String) {
        defaults.set(exceptions.filter { $0 != word }, forKey: Key.exceptions)
    }

    func clearExceptions() {
        defaults.removeObject(forKey: Key.exceptions)
    }
}

/// Starting Lad at login, through SMAppService (System Settings › General › Login Items).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
