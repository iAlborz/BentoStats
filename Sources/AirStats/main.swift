import AppKit

// Command-line modes short-circuit before any UI exists, so `--probe` works over
// SSH and in CI where there is no window server.
if DiagnosticsCLI.runIfRequested() {
    exit(0)
}

// Menu bar accessory: no Dock icon, no app menu. Set before `run()` so the app
// never flashes a Dock tile on launch.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
// Dark only, whatever the system's appearance: the panel, its cards and Settings are
// designed for dark. The menu bar item still follows the menu bar, which the system
// draws in its own appearance.
application.appearance = NSAppearance(named: .darkAqua)

let delegate = AppDelegate()
application.delegate = delegate
application.run()
