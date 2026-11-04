import Testing
import Foundation
@testable import AirStatKit
@testable import AirStatUI

@Suite("The menu bar item is always there")
struct MenuBarItemLayoutTests {

    /// The switch is gone. A file that turned it off loads, keeps its readouts, and
    /// gets the item back.
    @Test("a settings file that took the item out of the menu bar still loads")
    func hiddenFileLoads() throws {
        let json = Data(#"{"isVisible":false,"items":[{"metric":"gpuUsage","style":"text"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(MenuBarSettings.self, from: json)
        #expect(decoded.items.map(\.metric) == [.gpuUsage])
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
