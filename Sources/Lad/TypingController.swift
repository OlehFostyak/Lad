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

    private var engine = LadEngine()
    /// The app in front (never Lad itself), whose focus changes reset the typing.
    private var frontProcessID: pid_t?
    private var frontBundleID: String?
    private var appLayouts: LayoutMemory
    private var usage: UsageCounter
    private let settings: Settings
    private let inputSources: InputSources
    private let output = KeyboardOutput()
    private let selection: SelectionTransformer
    private let focus = FocusObserver()
    private let sound = NSSound(named: "Pop")
    private let hint = LayoutHint()
    private var rhythm = TypingRhythm()
    private var sources = SourceFilter()
    private var tap: EventTap?
    private var observers: [NSObjectProtocol] = []

    init(settings: Settings, inputSources: InputSources) {
        self.settings = settings
        self.inputSources = inputSources
        self.selection = SelectionTransformer(output: output)
        self.appLayouts = LayoutMemory(settings.appLayouts)
        self.usage = UsageCounter(counts: settings.usageCounts)
        engine.isAutomatic = settings.isAutomatic
        engine.fixesTwoCapitals = settings.fixesTwoCapitals
        engine.exceptions = Set(settings.exceptions)
        engine.learnedWords = Set(settings.learnedWords)
        inputSources.onSelectionChange = { [weak self] layoutID in self?.layoutDidChange(to: layoutID) }
        inputSources.onEnabledChange = { [weak self] in self?.refreshLayouts() }
        focus.onFocusChange = { [weak self] in self?.engine.reset() }
        observeWorkspace()
        frontProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        updateAppRules()
        refreshLayouts()
    }

    var remembersAppLayouts: Bool { settings.remembersAppLayouts }
    /// macOS switches input sources per document itself, which would fight Lad's memory.
    var systemSwitchesPerDocument: Bool { settings.systemSwitchesPerDocument }
    var rememberedAppCount: Int { appLayouts.layouts.count }

    /// Turning the memory off also forgets which apps it knew.
    func setRemembersAppLayouts(_ remembers: Bool) {
        settings.remembersAppLayouts = remembers
        if !remembers {
            forgetAppLayouts()
        }
        onStateChange?()
    }

    func forgetAppLayouts() {
        appLayouts = LayoutMemory()
        settings.appLayouts = [:]
        onStateChange?()
    }

    /// Terminals, and apps with one built in, keep Return as it is, never switch a word while it is
    /// typed and learn nothing from double Shift: the word may be a prompt's password (AppKind).
    private func updateAppRules() {
        let inTerminal = AppKind(bundleID: frontBundleID) != .regular
        engine.convertsOnReturn = settings.convertsOnReturn && !inTerminal
        engine.convertsWhileTyping = settings.convertsWhileTyping && !inTerminal
        engine.learnsWords = !inTerminal
    }

    var showsLayoutHint: Bool { settings.showsLayoutHint }

    /// Fixes over the last seven days and today.
    var fixCounts: (week: Int, today: Int) {
        let now = Date()
        return (usage.weekTotal(endingOn: now), usage.count(on: now))
    }

    func setShowsLayoutHint(_ shows: Bool) {
        settings.showsLayoutHint = shows
        onStateChange?()
    }

    var layouts: LayoutPair? { engine.layouts }
    var isTapRunning: Bool { tap?.isRunning ?? false }
    var isAutomatic: Bool { engine.isAutomatic }
    var convertsOnReturn: Bool { settings.convertsOnReturn }
    var convertsWhileTyping: Bool { settings.convertsWhileTyping }
    var fixesTwoCapitals: Bool { engine.fixesTwoCapitals }
    /// The words never converted again, most recent first.
    var exceptions: [String] { settings.exceptions.reversed() }
    /// The words always converted (fixed by hand once), most recent first.
    var learnedWords: [String] { settings.learnedWords.reversed() }

    /// A password field or a locked screen holds secure input; Lad sees no keys meanwhile.
    var isSecureInputOn: Bool { IsSecureEventInputEnabled() }

    /// Installs the event tap; false until Lad has the Accessibility permission.
    func startTap() -> Bool {
        let tap = self.tap ?? EventTap { [unowned self] event, origin in self.handle(event, from: origin) }
        self.tap = tap
        let started = tap.start()
        if started {
            focus.observe(processID: frontProcessID)
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

    func setConvertsOnReturn(_ converts: Bool) {
        settings.convertsOnReturn = converts
        updateAppRules()
        onStateChange?()
    }

    func setConvertsWhileTyping(_ converts: Bool) {
        settings.convertsWhileTyping = converts
        updateAppRules()
        onStateChange?()
    }

    func setFixesTwoCapitals(_ fixes: Bool) {
        settings.fixesTwoCapitals = fixes
        engine.fixesTwoCapitals = fixes
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

    func removeLearnedWord(_ word: String) {
        settings.removeLearnedWord(word)
        engine.learnedWords.remove(word)
        onStateChange?()
    }

    func clearLearnedWords() {
        settings.clearLearnedWords()
        engine.learnedWords = []
        onStateChange?()
    }

    /// Lad is quitting: put back a pasteboard a selection rewrite borrowed.
    func prepareForTermination() {
        selection.finishPendingRestore()
    }

    private func handle(_ event: InputEvent, from origin: InputOrigin) -> Bool {
        // Secure input (password fields, Terminal's Secure Keyboard Entry): Lad stays out entirely.
        guard !IsSecureEventInputEnabled() else {
            engine.reset()
            return false
        }
        // So it does for keys another program types (auto-typed passwords, text expanders), up to
        // the next word: the user may finish the one the program typed into.
        guard !isTypedByProgram(event, from: origin) else {
            engine.skipWord()
            return false
        }
        if case .keyDown = event {
            syncFrontApp()
        }
        // A remote desktop or virtual machine: the keys belong to another computer.
        guard AppKind(bundleID: frontBundleID) != .remote else {
            engine.reset()
            return false
        }
        if let hotkey = Hotkey.matching(event) {
            // A held shortcut repeats; the repeats are swallowed too, but only the first press acts.
            if case .keyDown(_, _, false) = event {
                perform(hotkey)
            }
            return true
        }
        let layoutBefore = engine.layouts?.current.id
        let result = engine.handle(event)
        remember(result)
        if let replacement = result.replacement {
            output.perform(replacement)
            select(replacement.layoutID)
            if result.isUndo {
                uncountFix()
            } else {
                countFix()
            }
            if settings.playsSound {
                sound?.stop()
                sound?.play()
            }
            if replacement.layoutID != layoutBefore {
                showHint(for: replacement.layoutID)
            }
        }
        if result.convertsSelection, let layouts = engine.layouts {
            rewriteSelection(allowsPasteboard: true) { text in
                TextConverter.convert(text, layouts: layouts).map { SelectionEdit(text: $0.text, layoutID: $0.layoutID) }
            }
        }
        return result.suppressesEvent
    }

    private func countFix() {
        usage.record(on: Date())
        settings.usageCounts = usage.counts
    }

    /// A fix turned back was no fix.
    private func uncountFix() {
        usage.remove(on: Date())
        settings.usageCounts = usage.counts
    }

    private func perform(_ hotkey: Hotkey) {
        switch hotkey {
        case .toggleAutomatic:
            // Only the automatic fixes stop; double Shift and the hotkeys keep working.
            setAutomatic(!engine.isAutomatic)
            showHint(engine.isAutomatic ? "Авто увімк." : "Авто вимк.", ukrainian: false)
        case .transliterate:
            rewriteSelection(allowsPasteboard: false) { Transliterator.ukrainianToLatin($0).map { SelectionEdit(text: $0, layoutID: nil) } }
        case .cycleCase:
            rewriteSelection(allowsPasteboard: false) { CaseCycle.next($0).map { SelectionEdit(text: $0, layoutID: nil) } }
        }
    }

    /// Rewrites the selection; a layout conversion also switches the layout and counts as a fix.
    private func rewriteSelection(allowsPasteboard: Bool, _ transform: @escaping SelectionTransformer.Transform) {
        engine.reset()
        selection.apply(transform, allowsPasteboard: allowsPasteboard) { [weak self] edit in
            guard let self, let layoutID = edit?.layoutID else { return }
            countFix()
            select(layoutID)
            engine.currentLayoutDidChange(to: layoutID)
            showHint(for: layoutID)
        }
    }

    /// Flashes the layout now in use next to the caret, after the event tap callback has returned.
    private func showHint(for layoutID: String) {
        let tables = [engine.layouts?.current, engine.layouts?.other].compactMap { $0 }
        guard let table = tables.first(where: { $0.id == layoutID }) else { return }
        let isUkrainian = table.language == .ukrainian
        showHint(isUkrainian ? "UA" : "EN", ukrainian: isUkrainian)
    }

    private func showHint(_ text: String, ukrainian: Bool) {
        guard settings.showsLayoutHint else { return }
        Task { [hint] in hint.show(text, ukrainian: ukrainian) }
    }

    /// Key presses posted by another program, or coming faster than a hand types.
    private func isTypedByProgram(_ event: InputEvent, from origin: InputOrigin) -> Bool {
        switch event {
        case let .keyDown(_, _, isRepeat):
            let wasCalibrated = sources.isCalibrated
            let isForeign = sources.isForeign(origin)
            if !wasCalibrated, sources.isCalibrated {
                Log.record(.foreignKeyFilterReady)
            }
            // A held key repeats at the system's pace, which may well be a program's.
            let isMachine = !isRepeat && rhythm.isMachine(at: origin.time)
            return isForeign || isMachine
        case .modifiersChanged:
            return origin.processID != 0 && sources.isCalibrated
        case .reset:
            return false
        }
    }

    /// Persists what the engine learned: exceptions and words fixed by hand.
    private func remember(_ result: EngineOutput) {
        if let word = result.forgottenWord {
            settings.removeLearnedWord(word)
        }
        if let word = result.learnedException {
            settings.addException(word)
        }
        if let word = result.learnedWord {
            settings.addLearnedWord(word)
        }
    }

    /// The engine already switched; if the system refuses, the engine re-reads the real layout.
    private func select(_ layoutID: String) {
        if !inputSources.select(layoutID) {
            refreshLayouts()
        }
    }

    private func layoutDidChange(to layoutID: String?) {
        guard let layoutID else { return }
        rememberLayout(layoutID)
        if let layouts = engine.layouts, layouts.current.id == layoutID || layouts.other.id == layoutID {
            engine.currentLayoutDidChange(to: layoutID)
            onStateChange?()
        } else {
            refreshLayouts()
        }
    }

    /// Not under secure input: macOS forces a Latin layout into password fields, which is not the
    /// app's layout, and keeps it there.
    private var isRememberingLayouts: Bool {
        settings.remembersAppLayouts && !settings.systemSwitchesPerDocument && !IsSecureEventInputEnabled()
    }

    /// The layout now in use belongs to the app in front, whoever switched it.
    private func rememberLayout(_ layoutID: String) {
        guard isRememberingLayouts, let bundleID = frontBundleID else { return }
        appLayouts.remember(layoutID, for: bundleID)
        settings.appLayouts = appLayouts.layouts
    }

    /// Brings back the layout last used in the app that came to the front.
    private func restoreLayout(for bundleID: String?) {
        guard isRememberingLayouts, let bundleID,
              let layoutID = appLayouts.layoutToRestore(
                  for: bundleID, current: inputSources.currentID, enabled: inputSources.enabledIDs
              ),
              inputSources.select(layoutID) else { return }
        engine.currentLayoutDidChange(to: layoutID)
        showHint(for: layoutID)
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

    /// The app switch notification can lag behind the keys: if another app is in front already,
    /// Lad catches up before the key, so it never retypes words of the previous app in this one.
    private func syncFrontApp() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != frontProcessID,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        appDidActivate(bundleID: app.bundleIdentifier, processID: app.processIdentifier)
    }

    private func appDidActivate(bundleID: String?, processID: pid_t?) {
        // Lad's own panel does not count as switching apps.
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        frontProcessID = processID
        frontBundleID = bundleID
        updateAppRules()
        focus.observe(processID: processID)
        restoreLayout(for: bundleID)
        // Apps can keep their own input source: re-read it rather than trust the engine's.
        if inputSources.currentID != engine.layouts?.current.id {
            refreshLayouts()
        } else {
            engine.reset()
        }
        onStateChange?()
    }
}
