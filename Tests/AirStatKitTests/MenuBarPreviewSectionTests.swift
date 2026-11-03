import Testing
import Foundation
@testable import AirStatKit
@testable import AirStatUI

/// A binding built for a readout can be read after Restore Defaults or an import has
/// replaced `menuBar.items` with a shorter list. It used to subscript by index there
/// and take the app down.
@MainActor
@Suite("Menu bar readout bindings outlive the list they were built for")
struct MenuBarPreviewSectionTests {

    private func store() -> SettingsStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SettingsStore(directory: dir, saveDebounce: .milliseconds(1))
    }

    /// Two more readouts than the app ships with, so the last one is guaranteed to sit
    /// past the end of the list a reset leaves behind. Counted off `defaultItems` rather
    /// than hardcoded: what the app ships with has changed before and will again, and
    /// the bug this covers is about the *difference* in length, not about four.
    private static let overflowCount = MenuBarSettings.defaultItems.count + 2

    private func overflowingReadouts(_ settings: SettingsStore) -> MenuBarItemConfig {
        let filler: [MenuBarMetric] = [.cpuUsage, .memoryUsage, .diskFree, .uptime,
                                       .batteryTime, .cpuFrequency, .memoryPressure]
        // Network throughput is always last, so the readout the bindings are built for
        // is the same graph-capable metric however long the list has to be.
        let metrics = Array(filler.prefix(Self.overflowCount - 1)) + [.networkThroughput]
        settings.update { s in
            s.menuBar.items = metrics
                .map { MenuBarItemConfig(metric: $0, style: $0.supportedStyles.first ?? .text) }
        }
        return settings.settings.menuBar.items[metrics.count - 1]
    }

    @Test("reading a binding after Restore Defaults returns the captured value")
    func readSurvivesReset() {
        let settings = store()
        let section = MenuBarPreviewSection(settings: settings, engine: nil)
        let last = overflowingReadouts(settings)

        let style = section.styleBinding(for: last)

        settings.resetSection(.menuBar)
        #expect(settings.settings.menuBar.items.count < Self.overflowCount)

        #expect(style.wrappedValue == last.style)
    }

    @Test("writing through a binding whose readout is gone changes nothing")
    func writeAfterResetIsInert() {
        let settings = store()
        let section = MenuBarPreviewSection(settings: settings, engine: nil)
        let last = overflowingReadouts(settings)
        let style = section.styleBinding(for: last)

        settings.resetSection(.menuBar)
        let afterReset = settings.settings.menuBar.items
        style.wrappedValue = .graph

        #expect(settings.settings.menuBar.items == afterReset)
    }

    @Test("a binding follows its readout across a reorder")
    func writeFollowsTheItem() {
        let settings = store()
        let section = MenuBarPreviewSection(settings: settings, engine: nil)
        let last = overflowingReadouts(settings)

        let displaced = settings.settings.menuBar.items[0]
        settings.update { $0.menuBar.items.reverse() }
        section.styleBinding(for: last).wrappedValue = .graph

        // An index-based binding would have written to whatever the reversal left at
        // the last index, which is the readout that started at index 0.
        #expect(settings.settings.menuBar.items.first { $0.id == last.id }?.style == .graph)
        #expect(settings.settings.menuBar.items.first { $0.id == displaced.id }?.style == displaced.style)
    }

    /// The list's checkbox could hide a readout, and nothing draws a hidden one now.
    @Test("adding a hidden readout's metric shows that readout, at the end")
    func addingShowsTheHiddenReadout() {
        let settings = store()
        let section = MenuBarPreviewSection(settings: settings, engine: nil)
        settings.update { s in
            s.menuBar.items = [MenuBarItemConfig(metric: .cpuUsage, style: .text),
                               MenuBarItemConfig(metric: .cpuTemperature, style: .graph, isEnabled: false),
                               MenuBarItemConfig(metric: .gpuUsage, style: .text)]
        }
        let hidden = settings.settings.menuBar.items[1]

        section.add(.cpuTemperature)

        let items = settings.settings.menuBar.items
        #expect(items.map(\.metric) == [.cpuUsage, .gpuUsage, .cpuTemperature])
        #expect(items.last?.id == hidden.id)
        #expect(items.last?.style == .graph)
        #expect(items.filter { !$0.isEnabled }.isEmpty)
    }

    @Test("adding a metric with no hidden readout adds a new one")
    func addingAppends() {
        let settings = store()
        let section = MenuBarPreviewSection(settings: settings, engine: nil)
        let before = settings.settings.menuBar.items

        section.add(.memoryUsage)

        let items = settings.settings.menuBar.items
        #expect(items.count == before.count + 1)
        #expect(items.last?.metric == .memoryUsage)
    }
}
