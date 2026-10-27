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

    @Test("Only the most recently used apps are kept")
    func keepsRecentApps() {
        var memory = LayoutMemory()
        for index in 0...LayoutMemory.maxApps {
            memory.remember("ua", for: "app\(index)")
        }
        memory.remember("us", for: "app1")
        memory.remember("us", for: "late")
        #expect(memory.layouts.count == LayoutMemory.maxApps)
        #expect(memory.layouts["app0"] == nil)
        #expect(memory.layouts["app2"] == nil)
        #expect(memory.layouts["app1"] == "us")
        #expect(memory.layouts["late"] == "us")
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
