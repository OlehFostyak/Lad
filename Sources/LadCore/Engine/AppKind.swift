/// What the app in front means for Lad's rules, by its bundle ID.
public enum AppKind: Sendable, Equatable {
    case regular
    /// A terminal, or an editor or tool with one built in: a word may be a password typed at a
    /// prompt that does not echo (sudo, ssh), and nothing turns secure input on there. Return never
    /// converts, words never switch while typed, double Shift fixes but learns nothing; the space
    /// still converts.
    case terminal
    /// A remote desktop or virtual machine window: the keys belong to another computer, whose
    /// password prompts turn no secure input on here, and retyping may not reach it. Lad stays out.
    case remote

    public init(bundleID: String?) {
        guard let bundleID else {
            self = .regular
            return
        }
        if Self.remoteApps.contains(bundleID) {
            self = .remote
        } else if Self.terminalApps.contains(bundleID) || Self.terminalAppPrefixes.contains(where: bundleID.hasPrefix) {
            self = .terminal
        } else {
            self = .regular
        }
    }

    static let terminalApps: Set<String> = [
        // Terminals.
        "com.apple.Terminal", "dev.warp.Warp-Stable", "dev.warp.Warp", "dev.warp.Warp-Preview",
        "com.googlecode.iterm2", "com.mitchellh.ghostty", "org.alacritty", "io.alacritty", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby", "com.raphaelamorim.rio",
        // Editors and tools with a built-in terminal (Devin and Windsurf share an ID).
        "com.exafunction.windsurf", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "dev.zed.Zed-Preview", "com.panic.Nova",
        "com.google.android.studio", "com.axosoft.gitkraken", "com.docker.docker",
    ]

    /// JetBrains IDEs (IntelliJ IDEA, PyCharm, WebStorm, GoLand, ...) all have a terminal.
    static let terminalAppPrefixes = ["com.jetbrains."]

    static let remoteApps: Set<String> = [
        "com.apple.ScreenSharing", "com.microsoft.rdc.macos", "com.microsoft.rdc.mac", "com.parallels.desktop.console",
        "com.vmware.fusion", "com.utmapp.UTM", "org.virtualbox.app.VirtualBoxVM", "com.realvnc.vncviewer",
        "com.teamviewer.TeamViewer", "com.philandro.anydesk", "com.p5sys.jump.mac.viewer",
    ]
}
