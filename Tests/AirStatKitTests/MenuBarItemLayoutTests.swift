import Testing
import Foundation
@testable import AirStatKit
@testable import AirStatUI

@Suite("The menu bar is one item for every readout, or none")
struct MenuBarItemLayoutTests {

    private let cpu = MenuBarItemConfig(metric: .cpuUsage, style: .text)
    private let memory = MenuBarItemConfig(metric: .memoryUsage, style: .text)
    private let gpu = MenuBarItemConfig(metric: .gpuUsage, style: .text)

    @Test("one item, however many readouts are enabled")
    func combinedIsOneItem() {
        let settings = MenuBarSettings(items: [cpu, memory, gpu])
        #expect(MenuBarItemLayout(settings: settings) == .combined)
    }

    @Test("hidden means no item, whatever the readouts say")
    func hiddenMeansNoItem() {
        #expect(MenuBarItemLayout(settings: MenuBarSettings(items: [cpu, memory], isVisible: false)) == .hidden)
        var off = cpu
        off.isEnabled = false
        #expect(MenuBarItemLayout(settings: MenuBarSettings(items: [off], isVisible: false)) == .hidden)
    }

    @Test("a settings file from before the hidden switch shows the item")
    func decodingDefaultsToVisible() throws {
        let json = Data(#"{"items":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(MenuBarSettings.self, from: json)
        #expect(decoded.isVisible)
    }

    /// The switch is gone; a file that turned it off still gets the one item.
    @Test("a settings file that asked for separate items gets the one item")
    func separateItemsAreCombined() throws {
        let json = Data(#"{"usesCombinedItem":false}"#.utf8)
        let decoded = try JSONDecoder().decode(MenuBarSettings.self, from: json)
        #expect(MenuBarItemLayout(settings: decoded) == .combined)
    }
}

@MainActor
@Suite("The status item keeps its place")
struct StatusItemControllerLayoutTests {

    /// The position the user dragged the item to is saved against this name.
    @Test("the item keeps the autosave name it has always had")
    func combinedAutosaveNameIsUnchanged() {
        #expect(StatusItemController.combinedAutosaveName == "AirStatsStatusItem")
    }
}
