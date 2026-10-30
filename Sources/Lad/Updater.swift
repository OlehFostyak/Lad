import AppKit
import LadCore
import Security

/// Finds newer releases of Lad on GitHub and installs them: download the archive, check that it is
/// signed with the same certificate as the running app (nobody else's build can be slipped in, and
/// the Accessibility grant carries over), swap the app bundle, relaunch.
///
/// The one place Lad touches the network or runs another program (ditto, and a shell that reopens
/// Lad). It asks GitHub only for Lad's latest release and its archive, and sends nothing else:
/// typed text never comes near it (the lint tests hold it to that).
final class Updater: ObservableObject {
    enum Status: Equatable {
        case idle, checking, installing, upToDate
        case failed(String)
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/OlehFostyak/Lad/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 3600

    @Published private(set) var status = Status.idle
    @Published private(set) var lastCheck: Date?
    private let settings: Settings
    private var timer: Timer?

    init(settings: Settings) {
        self.settings = settings
        lastCheck = settings.lastUpdateCheck
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Only an installed copy updates itself; a development build elsewhere is left alone.
    static var isInstalledCopy: Bool {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().path
        return ["/Applications", NSHomeDirectory() + "/Applications"].contains(folder)
    }

    /// Checks once a day while automatic updates are on, looking every hour so a Mac that slept
    /// catches up.
    func startDailyChecks() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard settings.updatesAutomatically, Self.isInstalledCopy else { return }
        if let lastCheck, Date.now.timeIntervalSince(lastCheck) < Self.checkInterval { return }
        check()
    }

    /// Checks now, and installs a newer release at once (the button means it; so does the switch).
    func check() {
        guard status != .checking, status != .installing else { return }
        status = .checking
        Task { [weak self] in
            do {
                var request = URLRequest(url: Self.latestReleaseURL)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.noRelease }
                self?.found(try JSONDecoder().decode(Release.self, from: data))
            } catch {
                self?.fail(error)
            }
        }
    }

    private func found(_ release: Release) {
        lastCheck = .now
        settings.lastUpdateCheck = lastCheck
        guard let asset = UpdateCheck.update(from: release, current: Self.currentVersion) else {
            status = .upToDate
            return
        }
        guard Self.isInstalledCopy else {
            fail(UpdateError.notInstalled)
            return
        }
        guard Self.isLadRelease(asset.downloadURL) else {
            fail(UpdateError.foreignSignature)
            return
        }
        Log.record(.updateFound)
        status = .installing
        Task { [weak self] in
            do {
                let (archive, _) = try await URLSession.shared.download(from: asset.downloadURL)
                try self?.replaceApp(withArchiveAt: archive)
            } catch {
                self?.fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        Log.record(.updateFailed)
        status = .failed(error.localizedDescription)
    }

    /// GitHub serves Lad's assets from its own release download path.
    private static func isLadRelease(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/OlehFostyak/Lad/releases/download/")
    }

    private func replaceApp(withArchiveAt archive: URL) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "lad-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let unzip = Process()
        unzip.executableURL = URL(filePath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", archive.path, folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        let newApp = folder.appending(path: "Lad.app")
        guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: newApp.path) else {
            throw UpdateError.badArchive
        }
        guard Self.isSignedLikeThisApp(newApp) else { throw UpdateError.foreignSignature }
        let current = Bundle.main.bundleURL
        _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
        Log.record(.updateInstalled)
        relaunch(current)
    }

    /// True when the bundle's signature is intact and meets the running app's designated
    /// requirement, which names its signing certificate: only a build signed by the same key passes.
    static func isSignedLikeThisApp(_ bundle: URL) -> Bool {
        var me: SecCode?
        var myStaticCode: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &myStaticCode) == errSecSuccess, let myStaticCode,
              SecCodeCopyDesignatedRequirement(myStaticCode, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(bundle as CFURL, [], &candidate) == errSecSuccess, let candidate
        else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(candidate, flags, requirement) == errSecSuccess
    }

    /// A shell waits for this process to quit, then opens the new copy (the single-instance guard
    /// would stop it while this one runs).
    private func relaunch(_ app: URL) {
        let shell = Process()
        shell.executableURL = URL(filePath: "/bin/sh")
        shell.arguments = [
            "-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
            app.path,
        ]
        try? shell.run()
        NSApp.terminate(nil)
    }

    enum UpdateError: LocalizedError {
        case noRelease, notInstalled, badArchive, foreignSignature

        var errorDescription: String? {
            switch self {
            case .noRelease: "GitHub не віддав останній реліз."
            case .notInstalled: "Ця копія не в Applications, тож сама не оновлюється."
            case .badArchive: "Завантажене оновлення пошкоджене."
            case .foreignSignature: "Оновлення підписане не ключем Lad, тож його не встановлено."
            }
        }
    }
}
