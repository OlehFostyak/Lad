/// The keyboard layout last used in each app, so that coming back to the app brings it back.
public struct LayoutMemory: Sendable, Equatable {
    /// At most this many apps are kept; the one not used for longest goes first.
    public static let maxApps = 100

    /// Bundle ID → input source ID.
    public private(set) var layouts: [String: String]
    /// Bundle IDs, least recently used first.
    private var order: [String]

    public init(_ layouts: [String: String] = [:]) {
        self.layouts = layouts
        self.order = layouts.keys.sorted()
        trim()
    }

    public mutating func remember(_ layoutID: String, for bundleID: String) {
        layouts[bundleID] = layoutID
        order.removeAll { $0 == bundleID }
        order.append(bundleID)
        trim()
    }

    /// The layout to select when the app comes to the front: nil when the app has none yet, it is
    /// already in use, or it is no longer enabled.
    public func layoutToRestore(for bundleID: String, current currentID: String?, enabled: Set<String>) -> String? {
        guard let layoutID = layouts[bundleID], layoutID != currentID, enabled.contains(layoutID) else { return nil }
        return layoutID
    }

    private mutating func trim() {
        while order.count > Self.maxApps {
            layouts[order.removeFirst()] = nil
        }
    }
}
