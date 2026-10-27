import AppKit
import LadCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// How often Lad checks for the Accessibility permission while it waits for it.
    private static let permissionPollInterval: TimeInterval = 1.5
    /// The first launch opens the panel once the menu bar icon is in place.
    private static let firstPanelDelay: Duration = .milliseconds(600)

    private let settings = Settings()
    private var inputSources: InputSources?
    private var controller: TypingController?
    private var model: PanelModel?
    private var statusItem: StatusItemController?
    private var permissionTimer: Timer?
    /// Keeps App Nap away: a napped process would answer its event tap late, and macOS would
    /// disable the tap.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isAnotherInstanceRunning() else {
            Log.record(.anotherInstanceRunning)
            NSApp.terminate(nil)
            return
        }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Lad watches typing to fix the keyboard layout"
        )
        FocusObserver.limitAccessibilityTimeouts()
        let inputSources = InputSources()
        let controller = TypingController(settings: settings, inputSources: inputSources)
        let model = PanelModel(controller: controller, settings: settings)
        let statusItem = StatusItemController(controller: controller, settings: settings, model: model)
        controller.onStateChange = { [weak statusItem, weak model] in
            statusItem?.refresh()
            if statusItem?.isPanelShown == true {
                model?.refresh()
            }
        }
        model.onIconStyleChange = { [weak statusItem] in statusItem?.refresh() }
        self.inputSources = inputSources
        self.controller = controller
        self.model = model
        self.statusItem = statusItem
        loadDictionaries(into: controller)
        let isFirstLaunch = !settings.didFirstLaunchSetup
        startTap(controller, prompting: !isFirstLaunch)
        if isFirstLaunch {
            setUpFirstLaunch(statusItem)
        }
    }

    /// Opening Lad again (Finder, Spotlight) shows its panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.prepareForTermination()
    }

    private func loadDictionaries(into controller: TypingController) {
        guard let directory = DictionaryLoader.directory() else {
            controller.dictionariesFailed()
            return
        }
        Task {
            do {
                controller.install(models: try await DictionaryLoader.load(from: directory))
            } catch {
                Log.record(.wordListsFailed)
                controller.dictionariesFailed()
            }
        }
    }

    /// Starts the tap now, or waits for the Accessibility permission and starts it once granted.
    /// The system prompt is skipped on the first launch: the panel explains the permission instead.
    private func startTap(_ controller: TypingController, prompting: Bool) {
        if Permissions.isTrusted, controller.startTap() { return }
        if prompting {
            Permissions.requestTrust()
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: Self.permissionPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard Permissions.isTrusted, controller.startTap() else { return }
                self?.permissionTimer?.invalidate()
                self?.permissionTimer = nil
            }
        }
    }

    /// The first launch turns on the login item (the owner asked for it) and opens the panel.
    private func setUpFirstLaunch(_ statusItem: StatusItemController) {
        settings.didFirstLaunchSetup = true
        do {
            try LoginItem.setEnabled(true)
        } catch {
            Log.record(.loginItemFailed)
        }
        Task {
            try? await Task.sleep(for: Self.firstPanelDelay)
            statusItem.showPanel()
        }
    }

    private static func isAnotherInstanceRunning() -> Bool {
        let current = NSRunningApplication.current
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != current.processIdentifier && !$0.isTerminated }
    }
}
