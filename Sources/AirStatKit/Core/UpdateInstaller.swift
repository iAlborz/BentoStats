import Foundation
import Security

/// Puts a release in place of the app: downloads it, checks that it is Bento Stats,
/// newer, signed by the same team and notarized by Apple, and swaps it in for the copy
/// on disk.
///
/// The signature check is the whole of the security here. A file the app downloads
/// itself carries no quarantine flag, so Gatekeeper never looks at it when it opens:
/// without this check, whatever was served at the download address would be run.
public struct UpdateInstaller: Sendable {

    /// The team every release must be signed by: the running copy's own.
    public let teamID: String
    public let bundleID: String

    public init(teamID: String, bundleID: String) {
        self.teamID = teamID
        self.bundleID = bundleID
    }

    /// The running copy's team, from its own signature. Nil for a copy signed ad hoc,
    /// as a build from source is, which has no team to hold a download to.
    public static var runningTeamID: String? {
        var running: SecCode?
        var onDisk: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &onDisk) == errSecSuccess, let onDisk,
              SecCodeCopySigningInformation(onDisk, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess else {
            return nil
        }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Replaces the app at `target` with `release`, if it passes. Relaunching into it is
    /// the caller's.
    public func install(_ release: UpdateRelease, over target: URL, newerThan current: String) async throws {
        let files = FileManager.default
        // On the same volume as the app, so the swap at the end is a rename.
        let work = try files.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: target, create: true)
        defer { try? files.removeItem(at: work) }

        let (download, response) = try await URLSession.shared.download(from: release.download)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.server(status) }
        let archive = work.appendingPathComponent(UpdateFeed.assetName)
        try files.moveItem(at: download, to: archive)

        // ditto, which wrote the archive, so the signature comes out as it went in.
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        try await run("/usr/bin/ditto", "-x", "-k", archive.path, unpacked.path)
        let contents = try files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.noApp }

        try check(app, newerThan: current)
        _ = try files.replaceItemAt(target, withItemAt: app)
    }

    private func check(_ app: URL, newerThan current: String) throws {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == bundleID else { throw UpdateError.notThisApp }
        guard let version = info?["CFBundleShortVersionString"] as? String,
              UpdateFeed.isVersion(version, newerThan: current) else { throw UpdateError.notNewer }

        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and notarized"
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw UpdateError.untrusted
        }
    }

    private func run(_ tool: String, _ arguments: String...) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            process.terminationHandler = { process in
                guard process.terminationStatus != 0 else { return continuation.resume() }
                let said = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(throwing: UpdateError.tool("\((tool as NSString).lastPathComponent) failed: "
                                                               + said.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
