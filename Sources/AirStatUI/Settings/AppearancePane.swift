import SwiftUI
import AppKit
import AirStatKit

/// How Bento Stats looks: light or dark, which layout the panel draws, and how its
/// charts are drawn.
///
/// The colours are the design's own: each card has its pair, chosen together, so there
/// is no longer a colour per metric to set here.
struct AppearancePane: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: settings.binding(\.general.appearance,
                                                            onChange: applyAppearance)) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section {
                Picker("Layout", selection: settings.binding(\.panel.style)) {
                    ForEach(PanelStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Panel")
            } footer: {
                SettingsFootnote("Bento and Bento Small each keep their own arrangement. To "
                                 + "arrange the cards, press and hold one, or Control-click it "
                                 + "and choose Edit Layout. Point at a card to see its detail. "
                                 + "MacBook is always dark.")
            }

            Section {
                Picker("Chart style", selection: settings.binding(\.charts.style)) {
                    ForEach(ChartStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Picker("Keep history for", selection: settings.binding(\.charts.historyDuration)) {
                    ForEach(ChartSettings.allowedDurations, id: \.self) { duration in
                        Text(SettingsLabels.duration(duration)).tag(duration)
                    }
                }
                Toggle("Show a 24-hour history in the panel",
                       isOn: settings.binding(\.panel.showsHistoryChart))
            } header: {
                Text("Charts")
            }
        }
        .settingsFormStyle()
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
