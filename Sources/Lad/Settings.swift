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
        static let fixesTwoCapitals = "fixesTwoCapitals"
        static let remembersAppLayouts = "remembersAppLayouts"
        static let showsLayoutHint = "showsLayoutHint"
        static let appLayouts = "appLayouts"
        static let exceptions = "exceptions"
        static let learnedWords = "learnedWords"
        static let playsSound = "playsSound"
        static let iconStyle = "iconStyle"
        static let didFirstLaunchSetup = "didFirstLaunchSetup"
        /// Per-app pause, removed in 0.1.1; its list is dropped on launch.
        static let removedExcludedApps = "excludedApps"
    }

    /// The longest exception or learned-word list kept; the oldest words go first.
    static let maxListLength = 500

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.automatic: true, Key.convertsOnReturn: true, Key.fixesTwoCapitals: true, Key.remembersAppLayouts: true,
            Key.showsLayoutHint: true,
            Key.iconStyle: IconStyle.keyboard.rawValue,
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

    var fixesTwoCapitals: Bool {
        get { defaults.bool(forKey: Key.fixesTwoCapitals) }
        set { defaults.set(newValue, forKey: Key.fixesTwoCapitals) }
    }

    var remembersAppLayouts: Bool {
        get { defaults.bool(forKey: Key.remembersAppLayouts) }
        set { defaults.set(newValue, forKey: Key.remembersAppLayouts) }
    }

    var showsLayoutHint: Bool {
        get { defaults.bool(forKey: Key.showsLayoutHint) }
        set { defaults.set(newValue, forKey: Key.showsLayoutHint) }
    }

    /// Bundle ID → input source ID of the layout last used in the app.
    var appLayouts: [String: String] {
        get { (defaults.dictionary(forKey: Key.appLayouts) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: Key.appLayouts) }
    }

    /// macOS's own "Automatically switch to a document's input source" (Keyboard › Input Sources),
    /// which would fight Lad's memory of layouts per app.
    var systemSwitchesPerDocument: Bool {
        let properties = UserDefaults(suiteName: "com.apple.HIToolbox")?.dictionary(forKey: "AppleGlobalTextInputProperties")
        return (properties?["TextInputGlobalPropertyPerContextInput"] as? Bool) ?? false
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

    /// A word is either an exception or learned, never both.
    func addException(_ word: String) {
        append(word, to: Key.exceptions)
        remove(word, from: Key.learnedWords)
    }

    func removeException(_ word: String) {
        remove(word, from: Key.exceptions)
    }

    func clearExceptions() {
        defaults.removeObject(forKey: Key.exceptions)
    }

    /// Words the user fixed by hand: Lad converts them on its own. Oldest first.
    var learnedWords: [String] {
        defaults.stringArray(forKey: Key.learnedWords) ?? []
    }

    func addLearnedWord(_ word: String) {
        append(word, to: Key.learnedWords)
        remove(word, from: Key.exceptions)
    }

    func removeLearnedWord(_ word: String) {
        remove(word, from: Key.learnedWords)
    }

    func clearLearnedWords() {
        defaults.removeObject(forKey: Key.learnedWords)
    }

    private func append(_ word: String, to key: String) {
        var list = (defaults.stringArray(forKey: key) ?? []).filter { $0 != word }
        list.append(word)
        defaults.set(Array(list.suffix(Self.maxListLength)), forKey: key)
    }

    private func remove(_ word: String, from key: String) {
        guard let list = defaults.stringArray(forKey: key), list.contains(word) else { return }
        defaults.set(list.filter { $0 != word }, forKey: key)
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
