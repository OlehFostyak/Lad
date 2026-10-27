import AppKit
import LadCore

/// What the settings popover shows. Its switches write straight back through `didSet`; `refresh()`
/// reads everything again from the controller and the settings.
final class PanelModel: ObservableObject {
    enum Health: Equatable {
        case working(pair: String)
        case manualOnly
        case secureInput
        case loadingWords
        case wordsFailed
        case needsAccess
        case needsLayouts
    }

    private static let keyboardSettingsURL = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    @Published private(set) var health = Health.loadingWords
    /// Most recent first.
    @Published private(set) var exceptions: [String] = []
    /// Most recent first.
    @Published private(set) var learnedWords: [String] = []
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var fixesThisWeek = 0
    @Published private(set) var fixesToday = 0
    /// macOS's own per-document switching is on, so Lad's memory of layouts per app rests.
    @Published private(set) var systemSwitchesPerDocument = false

    @Published var isAutomatic = true {
        didSet { apply { controller.setAutomatic(isAutomatic) } }
    }
    @Published var convertsOnReturn = true {
        didSet { apply { controller.setConvertsOnReturn(convertsOnReturn) } }
    }
    @Published var fixesTwoCapitals = true {
        didSet { apply { controller.setFixesTwoCapitals(fixesTwoCapitals) } }
    }
    @Published var remembersAppLayouts = true {
        didSet { apply { controller.setRemembersAppLayouts(remembersAppLayouts) } }
    }
    @Published var showsLayoutHint = true {
        didSet { apply { controller.setShowsLayoutHint(showsLayoutHint) } }
    }
    @Published var playsSound = false {
        didSet { apply { settings.playsSound = playsSound } }
    }
    @Published var iconStyle = IconStyle.keyboard {
        didSet { apply { settings.iconStyle = iconStyle; onIconStyleChange?() } }
    }
    @Published var launchesAtLogin = false {
        didSet { apply { setLoginItem(launchesAtLogin) } }
    }

    var onIconStyleChange: (() -> Void)?

    private let controller: TypingController
    private let settings: Settings
    private var isRefreshing = false

    init(controller: TypingController, settings: Settings) {
        self.controller = controller
        self.settings = settings
        refresh()
    }

    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    func refresh() {
        isRefreshing = true
        defer { isRefreshing = false }
        health = Self.health(of: controller)
        isAutomatic = controller.isAutomatic
        convertsOnReturn = controller.convertsOnReturn
        fixesTwoCapitals = controller.fixesTwoCapitals
        remembersAppLayouts = controller.remembersAppLayouts
        showsLayoutHint = controller.showsLayoutHint
        (fixesThisWeek, fixesToday) = controller.fixCounts
        systemSwitchesPerDocument = controller.systemSwitchesPerDocument
        exceptions = controller.exceptions
        learnedWords = controller.learnedWords
        playsSound = settings.playsSound
        iconStyle = settings.iconStyle
        launchesAtLogin = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
    }

    func removeException(_ word: String) {
        controller.removeException(word)
        refresh()
    }

    func clearExceptions() {
        controller.clearExceptions()
        refresh()
    }

    func removeLearnedWord(_ word: String) {
        controller.removeLearnedWord(word)
        refresh()
    }

    func clearLearnedWords() {
        controller.clearLearnedWords()
        refresh()
    }

    func grantAccess() {
        Permissions.requestTrust()
        Permissions.openAccessibilitySettings()
    }

    func openKeyboardSettings() {
        guard let url = URL(string: Self.keyboardSettingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func openLoginItems() {
        LoginItem.openSettings()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    /// Runs a change made in the popover; changes made by `refresh()` itself are not applied back.
    private func apply(_ change: () -> Void) {
        guard !isRefreshing else { return }
        change()
        refresh()
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            Log.record(.loginItemFailed)
        }
        if LoginItem.needsApproval {
            LoginItem.openSettings()
        }
    }

    private static func health(of controller: TypingController) -> Health {
        if !controller.isTapRunning { return .needsAccess }
        guard let layouts = controller.layouts else { return .needsLayouts }
        switch controller.dictionaries {
        case .loading: return .loadingWords
        case .failed: return .wordsFailed
        case .ready: break
        }
        if controller.isSecureInputOn { return .secureInput }
        if !controller.isAutomatic { return .manualOnly }
        // Latin first, whichever layout is in use.
        let names = [layouts.current, layouts.other].sorted { ($0.language == .english ? 0 : 1) < ($1.language == .english ? 0 : 1) }
        return .working(pair: names.map(\.name).joined(separator: " ⇄ "))
    }
}
