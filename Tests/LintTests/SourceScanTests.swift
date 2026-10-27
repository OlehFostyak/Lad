import Foundation
import Testing

/// Lad sees every key the user types, so the shipped code is held to a short list of what it may
/// touch: no network, no other processes or scripts, logging only through Log.record, disk and
/// pasteboard access only in the files that need them. `make verify` checks the built binary too.
@Suite("Source scans")
struct SourceScanTests {
    private struct SourceFile {
        let path: String
        let text: String
        var name: String { (path as NSString).lastPathComponent }
    }

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every file of the shipped targets; LadEval is a developer tool and is not scanned.
    private static let shipped: [SourceFile] = ["Sources/Lad", "Sources/LadCore"].flatMap { directory -> [SourceFile] in
        let url = root.appending(path: directory)
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL } ?? []
        return files.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.map { file in
            SourceFile(
                path: file.path.replacingOccurrences(of: root.path + "/", with: ""),
                text: (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            )
        }
    }

    @Test("The shipped sources exist and are all Swift")
    func onlySwift() {
        #expect(Self.shipped.count >= 15)
        for file in Self.shipped {
            #expect(file.path.hasSuffix(".swift"), "\(file.path) is not a Swift file")
        }
    }

    @Test("Imports stay on the allow-list")
    func imports() {
        let allowed: Set<String> = [
            "Foundation", "AppKit", "SwiftUI", "CoreGraphics", "Carbon", "ApplicationServices", "ServiceManagement", "LadCore",
        ]
        for file in Self.shipped {
            for line in file.text.split(separator: "\n") where line.hasPrefix("import ") || line.hasPrefix("@testable import ") {
                let module = String(line.split(separator: " ").last ?? "")
                let isAllowed = allowed.contains(module) || (module == "os" && file.name == "Log.swift")
                #expect(isAllowed, "\(file.path) imports \(module)")
            }
        }
    }

    @Test("No network, process, scripting or broadcast API", arguments: [
        "URLSession", "URLRequest", "NWConnection", "NWListener", "NWBrowser", "CFSocket", "CFStream", "CFReadStream",
        "CFWriteStream", "NSURLConnection", "WKWebView", "getaddrinfo", "socket(", "Host(", "NSHost(", "NSHost.current", "Process(", "NSTask",
        "NSAppleScript", "OSAScript", "postNotificationName", "://", "dlopen", "posix_spawn", "NSXPCConnection",
    ])
    func noOutboundAPI(api: String) {
        for file in Self.shipped {
            #expect(!file.text.contains(api), "\(file.path) uses \(api)")
        }
    }

    @Test("Logging only through Log.record", arguments: [
        "Logger(", "os_log", "NSLog", "privacy:", "print(", "debugPrint", "dump(", "fputs", "standardError",
        "standardOutput", "FileHandle",
    ])
    func loggingOnlyInLog(api: String) {
        for file in Self.shipped where file.name != "Log.swift" {
            #expect(!file.text.contains(api), "\(file.path) logs or prints through \(api)")
        }
    }

    @Test("Log events carry no free text: the only interpolation is a layout ID")
    func logEventsCarryNoText() throws {
        let log = try #require(Self.shipped.first { $0.name == "Log.swift" })
        for interpolation in log.text.components(separatedBy: "\\(").dropFirst() {
            #expect(interpolation.hasPrefix("id, privacy: .public)"), "Log.swift interpolates \(interpolation.prefix(30))")
        }
    }

    @Test("Disk and pasteboard access stay in their files")
    func confinedAccess() {
        let rules: [(api: String, files: Set<String>)] = [
            ("UserDefaults", ["Settings.swift"]),
            ("contentsOf", ["DictionaryLoader.swift"]),
            ("NSPasteboard", ["SelectionTransformer.swift"]),
            ("FileManager", []),
            (".write(", []),
            ("createFile", []),
            ("NSWorkspace.shared.open", ["Permissions.swift", "PanelModel.swift"]),
        ]
        for file in Self.shipped {
            for rule in rules where file.text.contains(rule.api) {
                #expect(rule.files.contains(file.name), "\(file.path) uses \(rule.api)")
            }
        }
    }

    @Test("The package has no dependencies, plugins or unsafe flags")
    func packageManifest() throws {
        let manifest = try String(contentsOf: Self.root.appending(path: "Package.swift"), encoding: .utf8)
        for token in [".package(", ".plugin(", "unsafeFlags"] {
            #expect(!manifest.contains(token), "Package.swift has \(token)")
        }
    }
}
