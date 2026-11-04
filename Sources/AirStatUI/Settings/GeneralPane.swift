import SwiftUI
import AppKit
import AirStatKit

struct GeneralPane: View {
    let settings: SettingsStore
    /// Live numbers for the menu bar preview, which falls back to fixtures without it.
    let engine: MetricsEngine?
    /// Absent unless this copy updates itself.
    var updater: Updater? = nil

    /// `LoginItem.synchronize` reports a real failure — a missing bundle, a
    /// revoked approval — and the toggle is worthless if that is swallowed.
    @State private var loginItemError: String?

    var body: some View {
        Form {
            // How Bento Stats looks, which was a pane of its own until its history and
            // chart settings went. It is always dark, and each card has its own colours.
            Section {
                LayoutPicker(selection: settings.binding(\.panel.style))
            } header: {
                Text("Appearance")
            } footer: {
                SettingsFootnote(String(localized: "Bento and Bento Small each keep their own arrangement. To arrange the cards, press and hold one, or Control-click it and choose Edit Layout. Point at a card to see its detail."))
            }

            MenuBarPreviewSection(settings: settings, engine: engine)

            Section {
                Toggle("Open Bento Stats at login",
                       isOn: settings.binding(\.general.launchAtLogin, onChange: applyLoginItem))
                if let loginItemError {
                    SettingsCaution(loginItemError)
                }
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
            return String(localized: "Left off, the Network module shows your local addresses only and Bento Stats contacts nothing.")
        }
        return String(localized: "Left off, the Network module shows your local addresses only, and the one thing Bento Stats contacts is GitHub, to check for updates.")
    }

    // MARK: Side effects

    private func applyLoginItem(_ enabled: Bool) {
        if let error = LoginItem.synchronize(enabled: enabled) {
            loginItemError = enabled
                ? String(localized: "macOS refused to register the login item: \(error.localizedDescription)")
                : String(localized: "macOS refused to remove the login item: \(error.localizedDescription)")
            // The stored preference must not claim something the system rejected.
            settings.update { $0.general.launchAtLogin = LoginItem.isEnabled }
        } else {
            loginItemError = nil
        }
    }
}

/// The panel's layouts, each over a picture of it, so the choice is made by looking.
///
/// The pictures are the panel itself, rendered offscreen on fixture data and kept as
/// files: four live panels in a settings window would cost what four open panels do.
/// The App Store's copy has its own, where a layout shows temperatures it cannot read.
private struct LayoutPicker: View {
    @Binding var selection: PanelStyle

    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.l) {
            ForEach(PanelStyle.allCases, id: \.self) { style in
                option(style)
            }
        }
        .padding(.vertical, Design.Space.xs)
    }

    private func option(_ style: PanelStyle) -> some View {
        let isSelected = style == selection
        let shape = RoundedRectangle(cornerRadius: Design.Radius.card + 2, style: .continuous)
        return Button {
            selection = style
        } label: {
            VStack(spacing: Design.Space.s) {
                Group {
                    if let image = Self.thumbnails[style] {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .padding(Design.Space.s)
                .frame(maxWidth: .infinity)
                .frame(height: Self.thumbnailHeight)
                .background(shape.fill(Color(nsColor: PanelWindow.backdropColor)))
                .overlay {
                    shape.strokeBorder(isSelected ? Design.Palette.accent : Design.Palette.separator,
                                       lineWidth: isSelected ? 2 : Design.Space.hairline)
                }
                Text(style.label)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Design.Palette.primaryText : Design.Palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private static let thumbnailHeight: CGFloat = 92

    private static let thumbnails: [PanelStyle: NSImage] = {
        var images: [PanelStyle: NSImage] = [:]
        for style in PanelStyle.allCases {
            let name = "Layout-\(style.rawValue)"
            let store = Capabilities.readsSensors ? nil : Logo.resourceURL(name + "-store", withExtension: "png")
            if let url = store ?? Logo.resourceURL(name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                images[style] = image
            }
        }
        return images
    }()
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
            return String(localized: "Bento Stats \(release.version) is available")
        }
        if updater.lastCheck != nil, updater.failure == nil {
            return String(localized: "Bento Stats \(updater.currentVersion) is up to date")
        }
        return String(localized: "Bento Stats \(updater.currentVersion)")
    }
}
