import AppKit
import Carbon
import LadCore

/// Connects the event tap to the engine and carries out what the engine decides: retyping,
/// switching layouts, converting selections, remembering exceptions.
final class TypingController {
    enum DictionaryState {
        case loading
        case ready
        case failed
    }

    /// Anything the panel or the icon shows changed.
    var onStateChange: (() -> Void)?
    private(set) var dictionaries = DictionaryState.loading
    private(set) var frontApp: NSRunningApplication?

    private var engine = LadEngine()
    private let settings: Settings
    private let inputSources: InputSources
    private let output = KeyboardOutput()
    private let selection: SelectionConverter
    private let focus = FocusObserver()
    private let sound = NSSound(named: "Pop")
    private var tap: EventTap?
    private var observers: [NSObjectProtocol] = []

    init(settings: Settings, inputSources: InputSources) {
        self.settings = settings
        self.inputSources = inputSources
        self.selection = SelectionConverter(output: output)
        engine.isAutomatic = settings.isAutomatic
        engine.exceptions = Set(settings.exceptions)
        inputSources.onSelectionChange = { [weak self] layoutID in self?.layoutDidChange(to: layoutID) }
        inputSources.onEnabledChange = { [weak self] in self?.refreshLayouts() }
        focus.onFocusChange = { [weak self] in self?.engine.reset() }
        observeWorkspace()
        frontApp = NSWorkspace.shared.frontmostApplication
        refreshLayouts()
    }

    var layouts: LayoutPair? { engine.layouts }
    var isTapRunning: Bool { tap?.isRunning ?? false }
    var isAutomatic: Bool { engine.isAutomatic }
    var pausedApps: Set<String> { settings.excludedApps }
    /// The words never converted again, most recent first.
    var exceptions: [String] { settings.exceptions.reversed() }

    /// A password field or a locked screen holds secure input; Lad sees no keys meanwhile.
    var isSecureInputOn: Bool { IsSecureEventInputEnabled() }

    /// Lad does nothing at all in a paused app, double Shift included.
    var isPausedInFrontApp: Bool {
        guard let bundleID = frontApp?.bundleIdentifier else { return false }
        return settings.excludedApps.contains(bundleID)
    }

    /// Installs the event tap; false until Lad has the Accessibility permission.
    func startTap() -> Bool {
        let tap = self.tap ?? EventTap { [unowned self] event in self.handle(event) }
        self.tap = tap
        let started = tap.start()
        if started {
            focus.observe(processID: frontApp?.processIdentifier)
        }
        onStateChange?()
        return started
    }

    func install(models: [LanguageModel]) {
        engine.detector = Detector(models: models)
        dictionaries = .ready
        onStateChange?()
    }

    func dictionariesFailed() {
        dictionaries = .failed
        onStateChange?()
    }

    func setAutomatic(_ isAutomatic: Bool) {
        settings.isAutomatic = isAutomatic
        engine.isAutomatic = isAutomatic
        onStateChange?()
    }

    func setPaused(_ paused: Bool, bundleID: String) {
        var excluded = settings.excludedApps
        if paused {
            excluded.insert(bundleID)
        } else {
            excluded.remove(bundleID)
        }
        settings.excludedApps = excluded
        engine.reset()
        onStateChange?()
    }

    func removeException(_ word: String) {
        settings.removeException(word)
        engine.exceptions.remove(word)
        onStateChange?()
    }

    func clearExceptions() {
        settings.clearExceptions()
        engine.exceptions = []
        onStateChange?()
    }

    /// Lad is quitting: put back a pasteboard a selection conversion borrowed.
    func prepareForTermination() {
        selection.finishPendingRestore()
    }

    private func handle(_ event: InputEvent) -> Bool {
        guard !isPausedInFrontApp else { return false }
        // Secure input (password fields, Terminal's Secure Keyboard Entry): Lad stays out entirely.
        guard !IsSecureEventInputEnabled() else {
            engine.reset()
            return false
        }
        let result = engine.handle(event)
        if let exception = result.learnedException {
            settings.addException(exception)
        }
        if let replacement = result.replacement {
            output.perform(replacement)
            select(replacement.layoutID)
            if settings.playsSound {
                sound?.stop()
                sound?.play()
            }
        }
        if result.convertsSelection, let layouts = engine.layouts {
            selection.convert(layouts: layouts) { [weak self] layoutID in
                guard let self, let layoutID else { return }
                select(layoutID)
                engine.currentLayoutDidChange(to: layoutID)
            }
        }
        return result.suppressesEvent
    }

    /// The engine already switched; if the system refuses, the engine re-reads the real layout.
    private func select(_ layoutID: String) {
        if !inputSources.select(layoutID) {
            refreshLayouts()
        }
    }

    private func layoutDidChange(to layoutID: String?) {
        guard let layoutID else { return }
        if let layouts = engine.layouts, layouts.current.id == layoutID || layouts.other.id == layoutID {
            engine.currentLayoutDidChange(to: layoutID)
            onStateChange?()
        } else {
            refreshLayouts()
        }
    }

    private func refreshLayouts() {
        engine.setLayouts(inputSources.currentPair())
        onStateChange?()
    }

    /// App switches move the focus; sleep, a locked screen or a switched user leave the typing behind.
    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let processID = app?.processIdentifier
            MainActor.assumeIsolated { self?.appDidActivate(bundleID: bundleID, processID: processID) }
        })
        let interruptions = [
            NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
        ]
        for name in interruptions {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engine.reset() }
            })
        }
    }

    private func appDidActivate(bundleID: String?, processID: pid_t?) {
        // Lad's own panel does not count as switching apps.
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        frontApp = processID.flatMap { NSRunningApplication(processIdentifier: $0) }
        focus.observe(processID: processID)
        // Apps can keep their own input source: re-read it rather than trust the engine's.
        if inputSources.currentID != engine.layouts?.current.id {
            refreshLayouts()
        } else {
            engine.reset()
        }
        onStateChange?()
    }
}
