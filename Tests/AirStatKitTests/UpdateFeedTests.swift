import Testing
import Foundation
@testable import AirStatKit

@Suite("Update feed")
struct UpdateFeedTests {

    @Test("Versions compare number by number")
    func versionOrder() {
        #expect(UpdateFeed.isVersion("1.1", newerThan: "1.0"))
        #expect(UpdateFeed.isVersion("1.0.1", newerThan: "1.0"))
        #expect(UpdateFeed.isVersion("1.10", newerThan: "1.9"))
        #expect(UpdateFeed.isVersion("2.0", newerThan: "1.9.9"))
        #expect(!UpdateFeed.isVersion("1.0", newerThan: "1.0"))
        #expect(!UpdateFeed.isVersion("1.0.0", newerThan: "1.0"))
        #expect(!UpdateFeed.isVersion("1.9", newerThan: "1.10"))
        #expect(!UpdateFeed.isVersion("0.9", newerThan: "1.0"))
    }

    @Test("A release is read from GitHub's answer, tag and zipped app")
    func parsesRelease() throws {
        let answer = """
        {"tag_name": "v1.1", "html_url": "https://github.com/iAlborz/BentoStats/releases/tag/v1.1",
         "draft": false, "prerelease": false,
         "assets": [
           {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
           {"name": "BentoStats.zip",
            "browser_download_url": "https://github.com/iAlborz/BentoStats/releases/download/v1.1/BentoStats.zip"}
         ]}
        """
        let release = try #require(try UpdateFeed.release(from: Data(answer.utf8)))
        #expect(release.version == "1.1")
        #expect(release.page.absoluteString == "https://github.com/iAlborz/BentoStats/releases/tag/v1.1")
        #expect(release.download.lastPathComponent == "BentoStats.zip")
    }

    @Test("A release without the zipped app offers nothing to install")
    func releaseWithoutApp() throws {
        let answer = """
        {"tag_name": "v1.1", "html_url": "https://github.com/iAlborz/BentoStats/releases/tag/v1.1", "assets": []}
        """
        #expect(try UpdateFeed.release(from: Data(answer.utf8)) == nil)
    }

    @Test("A build without the address never checks")
    func noAddressNoChecks() {
        // The test runner's Info.plist is not the app's, and carries no address.
        #expect(UpdateFeed.url == nil)
    }
}
