import AppKit
import LadCore

/// What the settings popover shows. Its switches write straight back through `didSet`; `refresh()`
/// reads everything again from the controller and the settings.
final class PanelModel: ObservableObject {
    enum Health: Equatable {
        case working(pair: String)
        case manualOnly
        case paused
        case secureInput
        case loadingWords
        case wordsFailed
        case needsAccess
        case needsLayouts
    }

    struct App: Identifiable, Equatable {
        /// The bundle ID.
        let id: String
        let name: String
    }

    private static let keyboardSettingsURL = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    @Published private(set) var health = Health.loadingWords
    /// The app in front (never Lad itself), which the pause switch acts on.
    @Published private(set) var frontApp: App?
    @Published private(set) var pausedApps: [App] = []
    /// Most recent first.
    @Published private(set) var exceptions: [String] = []
    @Published private(set) var loginNeedsApproval = false

    @Published var isAutomatic = true {
        didSet { apply { controller.setAutomatic(isAutomatic) } }
    }
    @Published var isFrontAppPaused = false {
        didSet { apply { if let id = frontApp?.id { controller.setPaused(isFrontAppPaused, bundleID: id) } } }
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
        frontApp = controller.frontApp.flatMap { app in
            app.bundleIdentifier.map { App(id: $0, name: app.localizedName ?? $0) }
        }
        isAutomatic = controller.isAutomatic
        isFrontAppPaused = controller.isPausedInFrontApp
        pausedApps = controller.pausedApps.sorted().map { App(id: $0, name: Self.appName(for: $0)) }
        exceptions = controller.exceptions
        playsSound = settings.playsSound
        iconStyle = settings.iconStyle
        launchesAtLogin = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
    }

    func resume(_ app: App) {
        controller.setPaused(false, bundleID: app.id)
        refresh()
    }

    func removeException(_ word: String) {
        controller.removeException(word)
        refresh()
    }

    func clearExceptions() {
        controller.clearExceptions()
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
        if controller.isPausedInFrontApp { return .paused }
        if controller.isSecureInputOn { return .secureInput }
        if !controller.isAutomatic { return .manualOnly }
        // Latin first, whichever layout is in use.
        let names = [layouts.current, layouts.other].sorted { ($0.language == .english ? 0 : 1) < ($1.language == .english ? 0 : 1) }
        return .working(pair: names.map(\.name).joined(separator: " ⇄ "))
    }

    private static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        let info = Bundle(url: url)?.localizedInfoDictionary ?? Bundle(url: url)?.infoDictionary
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }
}
