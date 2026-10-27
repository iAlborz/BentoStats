import SwiftUI
import AppKit
import AirStatKit

struct GeneralPane: View {
    let settings: SettingsStore
    /// Absent unless this copy updates itself.
    var updater: Updater? = nil

    /// `LoginItem.synchronize` reports a real failure — a missing bundle, a
    /// revoked approval — and the toggle is worthless if that is swallowed.
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Bento Stats at login",
                       isOn: settings.binding(\.general.launchAtLogin, onChange: applyLoginItem))
                if let loginItemError {
                    SettingsCaution(loginItemError)
                }
                Toggle("Show icon in the Dock",
                       isOn: settings.binding(\.general.showsDockIcon, onChange: applyDockIcon))
            } header: {
                Text("Startup")
            }

            if let updater {
                Section {
                    Toggle("Check for updates automatically",
                           isOn: settings.binding(\.general.checksForUpdates) { if $0 { updater.checkNow() } })
                    UpdateStatusRow(updater: updater)
                    if let failure = updater.failure {
                        SettingsCaution(failure)
                    }
                } header: {
                    Text("Updates")
                }
            }

            Section {
                Picker("Update interval", selection: settings.binding(\.general.updateInterval)) {
                    ForEach(GeneralSettings.allowedIntervals, id: \.self) { interval in
                        Text(SettingsLabels.interval(interval)).tag(interval)
                    }
                }
                Toggle("Slow down when the menu bar is hidden",
                       isOn: settings.binding(\.general.throttlesWhenOccluded))
                Toggle("Pause sampling on Low Power Mode",
                       isOn: settings.binding(\.general.pausesOnLowPower))
            } header: {
                Text("Sampling")
            }

            Section {
                Picker("Temperature", selection: settings.binding(\.general.temperatureUnit)) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                Picker("Network rate", selection: settings.binding(\.general.networkRateUnit)) {
                    ForEach(NetworkRateUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                Picker("Storage sizes", selection: settings.binding(\.general.byteUnitStyle)) {
                    ForEach(ByteUnitStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Toggle("Show the percent sign", isOn: settings.binding(\.general.showsPercentSign))
            } header: {
                Text("Units")
            }

            Section {
                Toggle("Look up my public IP address",
                       isOn: settings.binding(\.general.fetchesPublicIP))
            } header: {
                Text("Privacy")
            } footer: {
                SettingsFootnote(privacyFootnote)
            }
        }
        .settingsFormStyle()
    }

    private var privacyFootnote: String {
        guard updater != nil, settings.settings.general.checksForUpdates else {
            return "Left off, the Network module shows your local addresses only and Bento Stats contacts nothing."
        }
        return "Left off, the Network module shows your local addresses only, and the one thing "
            + "Bento Stats contacts is GitHub, to check for updates."
    }

    // MARK: Side effects

    /// Process-level state rather than a stored preference, so the store's value alone
    /// would change nothing until the next launch.
    private func applyDockIcon(_ shows: Bool) {
        NSApp.setActivationPolicy(shows ? .regular : .accessory)
        // Switching policy drops key window status; take it back so the settings
        // window the user is standing in does not slide behind everything.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyLoginItem(_ enabled: Bool) {
        if let error = LoginItem.synchronize(enabled: enabled) {
            loginItemError = "macOS refused to \(enabled ? "register" : "remove") the login item: \(error.localizedDescription)"
            // The stored preference must not claim something the system rejected.
            settings.update { $0.general.launchAtLogin = LoginItem.isEnabled }
        } else {
            loginItemError = nil
        }
    }
}

/// Where this copy stands: the version, when it last looked, and the one thing to do next.
private struct UpdateStatusRow: View {
    let updater: Updater

    var body: some View {
        LabeledContent {
            switch updater.activity {
            case .checking:
                ProgressView().controlSize(.small)
            case .installing:
                HStack(spacing: Design.Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Installing…").foregroundStyle(Design.Palette.secondaryText)
                }
            case .idle:
                if updater.available == nil {
                    Button("Check Now", action: updater.checkNow)
                } else if updater.failure == nil {
                    Button("Install", action: updater.install)
                } else {
                    Button("Download", action: updater.openReleasePage)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(headline)
                if let lastCheck = updater.lastCheck {
                    Text("Last checked \(lastCheck.formatted(.relative(presentation: .named)))")
                        .font(.callout)
                        .foregroundStyle(Design.Palette.secondaryText)
                }
            }
        }
    }

    private var headline: String {
        if let release = updater.available {
            return "Bento Stats \(release.version) is available"
        }
        if updater.lastCheck != nil, updater.failure == nil {
            return "Bento Stats \(updater.currentVersion) is up to date"
        }
        return "Bento Stats \(updater.currentVersion)"
    }
}
