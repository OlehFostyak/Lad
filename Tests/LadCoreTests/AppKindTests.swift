import Testing
@testable import LadCore

@Suite("App kinds")
struct AppKindTests {
    @Test("Terminals and editors with a terminal", arguments: [
        "com.apple.Terminal", "dev.warp.Warp-Stable", "com.exafunction.windsurf", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.axosoft.gitkraken",
    ])
    func terminals(bundleID: String) {
        #expect(AppKind(bundleID: bundleID) == .terminal)
    }

    @Test("Remote desktops and virtual machines", arguments: [
        "com.apple.ScreenSharing", "com.microsoft.rdc.macos", "com.parallels.desktop.console", "com.utmapp.UTM",
        "com.teamviewer.TeamViewer", "com.philandro.anydesk",
    ])
    func remote(bundleID: String) {
        #expect(AppKind(bundleID: bundleID) == .remote)
    }

    @Test("Everything else, and an app without an ID, is regular", arguments: [
        "ru.keepcoder.Telegram", "com.apple.Safari", "com.apple.dt.Xcode", "com.jetbrainsx.fake", "",
    ])
    func regular(bundleID: String) {
        #expect(AppKind(bundleID: bundleID) == .regular)
        #expect(AppKind(bundleID: nil) == .regular)
    }
}
