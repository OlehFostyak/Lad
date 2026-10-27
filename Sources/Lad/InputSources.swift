import AppKit
import Carbon
import LadCore

/// Watches the keyboard layouts: the one in use and the enabled ones.
final class InputSources {
    /// The selected layout changed, by Lad or by hand; the argument is its ID.
    var onSelectionChange: ((String?) -> Void)?
    /// The enabled layouts changed (System Settings › Keyboard › Input Sources).
    var onEnabledChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = DistributedNotificationCenter.default()
        let selected = NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        let enabled = NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)
        observers.append(center.addObserver(forName: selected, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSelectionChange?(SystemLayouts.currentID()) }
        })
        observers.append(center.addObserver(forName: enabled, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEnabledChange?() }
        })
    }

    /// The layout in use and its partner of the other language; nil without a Latin and a Cyrillic layout.
    func currentPair() -> LayoutPair? {
        guard let currentID = SystemLayouts.currentID() else { return nil }
        return LayoutPair.choose(currentID: currentID, from: SystemLayouts.enabled())
    }

    /// False when the system refused; the caller must then re-read the layout in use.
    @discardableResult
    func select(_ layoutID: String) -> Bool {
        let selected = SystemLayouts.select(id: layoutID)
        if !selected {
            Log.record(.layoutNotSelected(id: layoutID))
        }
        return selected
    }

    var currentID: String? { SystemLayouts.currentID() }
}
