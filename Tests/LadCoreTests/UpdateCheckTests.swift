import Foundation
import Testing
@testable import LadCore

@Suite("Update check")
struct UpdateCheckTests {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, assets: [String]) throws -> Release {
        let list = assets.map { #"{"name": "\#($0)", "browser_download_url": "https://github.com/OlehFostyak/Lad/releases/download/\#(tag)/\#($0)"}"# }
        let json = #"{"tag_name": "\#(tag)", "draft": \#(draft), "prerelease": \#(prerelease), "assets": [\#(list.joined(separator: ","))]}"#
        return try JSONDecoder().decode(Release.self, from: Data(json.utf8))
    }

    @Test("Versions compare part by part, missing parts are 0, a v is ignored")
    func comparesVersions() throws {
        #expect(try #require(AppVersion("0.3.1")) < #require(AppVersion("v0.3.10")))
        #expect(try #require(AppVersion("1.0")) == #require(AppVersion("1.0.0")))
        #expect(AppVersion("1.x") == nil)
        #expect(AppVersion("1..2") == nil)
    }

    @Test("A newer published release yields its zip")
    func findsNewerZip() throws {
        let newer = try release("v0.4.0", assets: ["Lad-0.4.0.dmg", "Lad-0.4.0.zip"])
        #expect(UpdateCheck.update(from: newer, current: "0.3.1")?.name == "Lad-0.4.0.zip")
    }

    @Test("The same or an older version, drafts, prereleases and releases without the zip yield nothing")
    func ignoresOthers() throws {
        #expect(UpdateCheck.update(from: try release("v0.3.1", assets: ["Lad-0.3.1.zip"]), current: "0.3.1") == nil)
        #expect(UpdateCheck.update(from: try release("v0.3.0", assets: ["Lad-0.3.0.zip"]), current: "0.3.1") == nil)
        #expect(UpdateCheck.update(from: try release("v0.4.0", draft: true, assets: ["Lad-0.4.0.zip"]), current: "0.3.1") == nil)
        #expect(UpdateCheck.update(from: try release("v0.4.0", prerelease: true, assets: ["Lad-0.4.0.zip"]), current: "0.3.1") == nil)
        #expect(UpdateCheck.update(from: try release("v0.4.0", assets: ["Lad-0.4.0.dmg"]), current: "0.3.1") == nil)
    }
}
