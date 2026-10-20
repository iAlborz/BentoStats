import SwiftUI
import AppKit
import AirStatKit

/// The app, and where it came from.
///
/// About the app rather than about the Mac: the panel already shows the machine, and
/// shows it better. The settings file's import, export and full reset went too: with
/// the panel arranged in the panel itself, there is too little in the settings file to
/// be worth carrying between Macs or wiping from here.
struct AboutPane: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: Design.Space.xl) {
                    LogoMark(size: 52)
                        .foregroundStyle(Design.Palette.primaryText)
                    VStack(alignment: .leading, spacing: Design.Space.xxs) {
                        Text("Bento Stats").font(.title2.weight(.medium))
                        Text(versionText).foregroundStyle(Design.Palette.secondaryText)
                        Text("Based on AirStats 1.5")
                            .font(.callout)
                            .foregroundStyle(Design.Palette.tertiaryText)
                    }
                    Spacer()
                }
                .padding(.vertical, Design.Space.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Bento Stats, \(versionText), based on AirStats 1.5")
                Link("AirStats on GitHub", destination: URL(string: "https://github.com/byrencheema/airstats")!)
            } footer: {
                if let diagnostic = settings.loadDiagnostic {
                    SettingsCaution(diagnostic)
                }
            }
        }
        .settingsFormStyle()
    }

    private var versionText: String {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            // Running the bare SwiftPM binary rather than the assembled .app.
            return "Development build"
        }
        return "Version \(short)"
    }
}
