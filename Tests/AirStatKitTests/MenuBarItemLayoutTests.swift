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

    /// Show / Hide Menu Bar Item went with the switch. A shortcut someone bound to it
    /// must not cost them the shortcuts bound to anything else.
    @Test("a shortcut for the removed action is dropped on its own")
    func removedShortcutIsDropped() throws {
        let shortcut = #"{"keyCode":35,"modifierFlags":1572864,"characters":"p"}"#
        let json = Data(#"{"bindings":["toggleMenuBarItem",\#(shortcut),"togglePanel",\#(shortcut)]}"#.utf8)
        let decoded = try JSONDecoder().decode(ShortcutSettings.self, from: json)
        #expect(decoded.bindings.keys.sorted { $0.rawValue < $1.rawValue } == [.togglePanel])
        #expect(decoded.bindings[.togglePanel]?.keyCode == 35)
    }

    @Test("shortcuts survive a round trip")
    func shortcutsRoundTrip() throws {
        let original = ShortcutSettings(bindings: [
            .togglePanel: KeyboardShortcut(keyCode: 35, modifierFlags: 1_572_864, characters: "p"),
            .openSettings: KeyboardShortcut(keyCode: 43, modifierFlags: 1_048_576, characters: ","),
        ])
        let decoded = try JSONDecoder().decode(ShortcutSettings.self,
                                               from: JSONEncoder().encode(original))
        #expect(decoded == original)
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
