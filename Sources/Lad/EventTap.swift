import AppKit
import CoreGraphics
import LadCore

/// The session event tap: it sees key presses, modifier changes and clicks before apps do, and may
/// drop a key press that Lad retypes. Lad's own synthetic events pass untouched.
final class EventTap {
    /// What the tap callback reads from an event, before handing it to the main actor.
    fileprivate enum Observation: Sendable {
        case input(InputEvent, InputOrigin)
        /// The system disabled the tap (a callback timeout or user input).
        case disabled
        case ignored
    }

    /// Returns true to drop the event.
    typealias Handler = (InputEvent, InputOrigin) -> Bool

    private let handler: Handler
    private var port: CFMachPort?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool {
        port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    /// Installs the tap; false without the Accessibility permission.
    func start() -> Bool {
        if port != nil { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: eventTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        Log.record(.tapInstalled)
        return true
    }

    fileprivate func process(_ observation: Observation) -> Bool {
        switch observation {
        case let .input(event, origin):
            return handler(event, origin)
        case .disabled:
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            Log.record(.tapReenabled)
            _ = handler(.reset, InputOrigin(processID: 0, time: ProcessInfo.processInfo.systemUptime))
            return false
        case .ignored:
            return false
        }
    }

    fileprivate nonisolated static func observe(_ type: CGEventType, _ event: CGEvent) -> Observation {
        let isLads = event.getIntegerValueField(.eventSourceUserData) == KeyboardOutput.marker
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return .disabled
        case .keyDown where !isLads:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return .input(.keyDown(keyCode: keyCode, modifiers: modifiers(of: event.flags), isRepeat: isRepeat), origin(of: event))
        case .flagsChanged where !isLads:
            let origin = origin(of: event)
            return .input(.modifiersChanged(modifiers(of: event.flags), time: origin.time), origin)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return .input(.reset, origin(of: event))
        default:
            return .ignored
        }
    }

    private nonisolated static func origin(of event: CGEvent) -> InputOrigin {
        InputOrigin(processID: event.getIntegerValueField(.eventSourceUnixProcessID), time: time(of: event))
    }

    /// When the event happened, in seconds since startup: its own time stamp, so key presses that
    /// queue up while the main thread is busy keep their real spacing. Events posted without one
    /// count from when they arrive.
    private nonisolated static func time(of event: CGEvent) -> TimeInterval {
        let now = ProcessInfo.processInfo.systemUptime
        guard let time = NSEvent(cgEvent: event)?.timestamp, time > 0, time <= now else { return now }
        return time
    }

    private nonisolated static func modifiers(of flags: CGEventFlags) -> Modifiers {
        var modifiers: Modifiers = []
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        if flags.contains(.maskAlphaShift) { modifiers.insert(.capsLock) }
        return modifiers
    }
}

/// The C callback. The tap's run loop source is on the main run loop, so it runs on the main thread;
/// clicks are never dropped.
private nonisolated func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    let observation = EventTap.observe(type, event)
    let drops = MainActor.assumeIsolated { tap.process(observation) }
    let isKeyDown = type == .keyDown
    return drops && isKeyDown ? nil : Unmanaged.passUnretained(event)
}
