import Foundation

/// A version like "1.2.3" (a leading "v", as in release tags, is ignored). Missing parts count as 0.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// A GitHub release, as much of it as the updater needs.
public struct Release: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    public let tag: String
    public let assets: [Asset]
    public let isDraft: Bool
    public let isPrerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case assets
        case isDraft = "draft"
        case isPrerelease = "prerelease"
    }

    public var version: AppVersion? { AppVersion(tag) }
}

/// Which release Lad installs. The network part lives in the app's Updater, never in LadCore.
public enum UpdateCheck {
    /// The archive of a published release newer than `current` (`Lad-<version>.zip`, which
    /// `make release` packs; the disk image next to it is for people), or nil.
    public static func update(from release: Release, current: String) -> Release.Asset? {
        guard !release.isDraft, !release.isPrerelease,
              let latest = release.version, let running = AppVersion(current), running < latest
        else { return nil }
        return release.assets.first { $0.name == "Lad-\(latest).zip" }
    }
}
