import Testing
@testable import LadCore

@Suite("Layout per app")
struct LayoutMemoryTests {
    private let enabled: Set<String> = ["us", "ua"]

    @Test("The last layout used in an app comes back")
    func restoresLastLayout() {
        var memory = LayoutMemory()
        memory.remember("us", for: "dev.warp.Warp-Stable")
        memory.remember("ua", for: "ru.keepcoder.Telegram")
        memory.remember("ua", for: "dev.warp.Warp-Stable")
        #expect(memory.layoutToRestore(for: "dev.warp.Warp-Stable", current: "us", enabled: enabled) == "ua")
        #expect(memory.layoutToRestore(for: "ru.keepcoder.Telegram", current: "us", enabled: enabled) == "ua")
    }

    @Test("Nothing to do for a new app, the layout in use or a disabled layout")
    func restoresNothing() {
        let memory = LayoutMemory(["app": "ua", "old": "ru"])
        #expect(memory.layoutToRestore(for: "new", current: "us", enabled: enabled) == nil)
        #expect(memory.layoutToRestore(for: "app", current: "ua", enabled: enabled) == nil)
        #expect(memory.layoutToRestore(for: "old", current: "us", enabled: enabled) == nil)
        #expect(memory.layouts == ["app": "ua", "old": "ru"])
    }
}
