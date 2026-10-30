import AppKit
import Observation
import AirStatKit

/// The copy of Bento Stats downloaded from GitHub keeping itself current: a check for a
/// newer release once a day, and an install the user asks for from the panel, from
/// Settings or from the notification that announces it.
///
/// Absent everywhere else. The App Store copy is updated by the store, which allows no
/// other way, and a build from source has no feed address; see `UpdateFeed.url`.
@MainActor
@Observable
public final class Updater {

    public enum Activity: Equatable, Sendable {
        case idle
        case checking
        case installing
    }

    /// The newer release, from the moment a check finds it.
    public private(set) var available: UpdateRelease?
    public private(set) var activity: Activity = .idle
    public private(set) var lastCheck: Date?
    /// Why the last check or install did not go through. Nil once one does.
    public private(set) var failure: String?

    public let currentVersion: String

    @ObservationIgnored private let feed: URL
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let authority: NotificationAuthority
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var schedule: Task<Void, Never>?

    private static let interval: Duration = .seconds(24 * 60 * 60)
    private static let notificationID = "update"
    /// The version last announced, so a release is announced once and not every day.
    private static let announcedKey = "updates.announcedVersion"

    /// Nil unless this copy updates itself.
    public init?(settings: SettingsStore, authority: NotificationAuthority,
                 defaults: UserDefaults = .standard) {
        guard let feed = UpdateFeed.url,
              let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        self.feed = feed
        self.currentVersion = version
        self.settings = settings
        self.authority = authority
        self.defaults = defaults
    }

    public func start() {
        authority.onOpen(Self.notificationID) { [weak self] in self?.install() }
        schedule = Task { [weak self] in
            // A minute in, so the check is not one more thing happening at login.
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                if self?.settings.settings.general.checksForUpdates == true {
                    await self?.check()
                }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    public func stop() {
        schedule?.cancel()
        schedule = nil
        authority.onOpen(Self.notificationID, run: nil)
    }

    /// The Check Now button, and turning automatic checks back on.
    public func checkNow() {
        Task { await check() }
    }

    private func check() async {
        guard activity == .idle else { return }
        activity = .checking
        defer { activity = .idle }
        do {
            let latest = try await UpdateFeed.latest(from: feed)
            lastCheck = Date()
            failure = nil
            WindowLog.log("update check: latest \(latest?.version ?? "none"), running \(currentVersion)")
            if let latest, UpdateFeed.isVersion(latest.version, newerThan: currentVersion) {
                available = latest
                announce(latest)
            } else {
                available = nil
            }
        } catch {
            failure = String(localized: "Couldn't check for updates. \(error.localizedDescription)")
            WindowLog.log("update check failed: \(error)")
        }
    }

    /// Downloads the release, swaps it in for this copy and relaunches into it.
    public func install() {
        guard let release = available, activity == .idle else { return }
        guard let team = UpdateInstaller.runningTeamID, let bundleID = Bundle.main.bundleIdentifier else {
            failure = String(localized: "This copy is not signed, so it cannot check an update's signature. Download it instead.")
            return
        }
        activity = .installing
        failure = nil
        let target = Bundle.main.bundleURL
        Task {
            do {
                try await UpdateInstaller(teamID: team, bundleID: bundleID)
                    .install(release, over: target, newerThan: currentVersion)
                relaunch(target)
            } catch {
                failure = String(localized: "Couldn't install the update. \(error.localizedDescription)")
                activity = .idle
                WindowLog.log("update install failed: \(error)")
            }
        }
    }

    /// The release page, for installing by hand when the install cannot.
    public func openReleasePage() {
        if let page = available?.page { NSWorkspace.shared.open(page) }
    }

    // MARK: Private

    private func announce(_ release: UpdateRelease) {
        guard defaults.string(forKey: Self.announcedKey) != release.version else { return }
        if authority.request("update notices") {
            authority.post(identifier: Self.notificationID,
                           title: String(localized: "Bento Stats \(release.version) is available"),
                           body: String(localized: "Click to install it."))
            defaults.set(release.version, forKey: Self.announcedKey)
        } else if authority.state == .requesting {
            // The answer comes from a prompt the user may leave up for a while, or, once
            // they have allowed notifications, a moment after asking. Ask again then.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.announce(release)
            }
        }
    }

    /// Quits the ordinary way, which saves the day's history, and leaves a shell behind
    /// to open the new copy once this process has gone, so the two never run together.
    private func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c",
                             "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; "
                             + "do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                             app.path]
        do {
            try process.run()
        } catch {
            failure = String(localized: "The update is installed. Quit and reopen Bento Stats to finish.")
            activity = .idle
            return
        }
        NSApp.terminate(nil)
    }
}
