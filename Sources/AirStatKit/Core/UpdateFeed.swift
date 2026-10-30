import Foundation

/// A release of Bento Stats on GitHub that this copy could update to.
public struct UpdateRelease: Equatable, Sendable {
    /// What people call it, `1.1`, from the tag `v1.1`.
    public var version: String
    /// The release's page, with its notes and the download for installing by hand.
    public var page: URL
    /// The zipped app the installer downloads.
    public var download: URL

    public init(version: String, page: URL, download: URL) {
        self.version = version
        self.page = page
        self.download = download
    }
}

/// How the copy of Bento Stats downloaded from GitHub learns of a newer release.
///
/// GitHub's API rather than an appcast: the release page is already where the download
/// lives, so a check is one request for the latest release, and nothing has to be
/// published beside it. Only that copy asks. Scripts/direct.sh writes the address into
/// its Info.plist; the App Store copy, which the store updates, and a build from source
/// carry none, so neither of them ever checks.
public enum UpdateFeed {

    /// The Info.plist key Scripts/direct.sh writes the address under.
    public static let infoKey = "BentoStatsReleasesURL"
    /// The asset the installer downloads, under the same name on every release: the app,
    /// zipped, beside the .dmg people download by hand. An app that opens a disk image
    /// needs the user's leave to read a removable volume, which would turn every update
    /// into a permission prompt; a zip needs none.
    public static let assetName = "BentoStats.zip"

    /// The address this copy checks, or nil when it does not update itself. The sandbox
    /// test is a second guard: the App Store copy must never update itself, whatever its
    /// Info.plist says.
    public static var url: URL? {
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil,
              let address = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String else {
            return nil
        }
        return URL(string: address)
    }

    /// Asks for the latest release. Nil when there is none yet, or when it has nothing
    /// to install.
    public static func latest(from url: URL) async throws -> UpdateRelease? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // What GitHub answers for a repository with no releases.
        if status == 404 { return nil }
        guard status == 200 else { throw UpdateError.server(status) }
        return try release(from: data)
    }

    /// The release GitHub's answer for `releases/latest` describes.
    static func release(from data: Data) throws -> UpdateRelease? {
        struct Answer: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        guard let app = answer.assets.first(where: { $0.name == assetName }) else { return nil }
        let tag = answer.tag_name
        return UpdateRelease(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                             page: answer.html_url, download: app.browser_download_url)
    }

    /// Whether `candidate` is a later version than `current`, compared number by number:
    /// 1.10 comes after 1.9, and 1.0.1 after 1.0.
    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func numbers(_ version: String) -> [Int] { version.split(separator: ".").map { Int($0) ?? 0 } }
        let new = numbers(candidate), old = numbers(current)
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

/// Why a check or an install did not go through, in words for the panel and Settings.
public enum UpdateError: LocalizedError, Equatable {
    case server(Int)
    case noApp
    case notThisApp
    case notNewer
    case untrusted
    case tool(String)

    public var errorDescription: String? {
        switch self {
        case .server(let status): return String(localized: "GitHub answered with status \(status).")
        case .noApp: return String(localized: "The download holds no app.")
        case .notThisApp: return String(localized: "The download is not Bento Stats.")
        case .notNewer: return String(localized: "The download is not a newer version.")
        case .untrusted: return String(localized: "The download is not signed by Bento Stats' developer and notarized by Apple.")
        case .tool(let message): return message
        }
    }
}
