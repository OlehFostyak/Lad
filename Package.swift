// swift-tools-version: 6.2
// 6.2+ is required for .macOS(.v26) and .defaultIsolation.
import PackageDescription

// The app target defaults to the main actor: AppKit, the event tap and the TIS calls all run there.
let ui: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Lad",
    // Deployment 26.0, built with the macOS 27 SDK of the Command Line Tools (no Xcode).
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Lad", targets: ["Lad"]),
        .executable(name: "lad-eval", targets: ["LadEval"]),
    ],
    targets: [
        // Keyboard tables, language models, the word tracker and its decisions. No AppKit.
        .target(name: "LadCore", linkerSettings: [.linkedFramework("Carbon")]),
        // The menu bar app: event tap, input sources, synthetic typing, settings.
        // No `resources:` here: the Makefile assembles the bundle by hand.
        .executableTarget(name: "Lad", dependencies: ["LadCore"], swiftSettings: ui),
        // Offline quality report for the detector and the layout fixture dump (make eval, make fixtures).
        .executableTarget(name: "LadEval", dependencies: ["LadCore"]),
        // Reads Resources/Dictionaries through #filePath.
        .testTarget(name: "LadCoreTests", dependencies: ["LadCore"], resources: [.copy("Fixtures")]),
        // Source scans: no networking APIs, no print().
        .testTarget(name: "LintTests"),
    ],
    swiftLanguageModes: [.v6]
)
