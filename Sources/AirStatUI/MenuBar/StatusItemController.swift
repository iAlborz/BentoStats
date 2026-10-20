import AppKit
import AirStatKit

/// What the menu bar is currently made of: one item drawing every readout, or none.
enum MenuBarItemLayout: Equatable {
    case combined
    /// The user has taken the app out of the menu bar. Nothing is installed, and the
    /// controller reports that explicit absence to its visibility callback.
    case hidden

    init(settings: MenuBarSettings) {
        self = settings.isVisible ? .combined : .hidden
    }
}

/// Owns the app's `NSStatusItem`s and the custom views drawn inside them.
///
/// The menu bar is the most scrutinised surface in the app: it sits two pixels from
/// Apple's own glyphs, redraws constantly, and must never jitter, blur, or push its
/// neighbours around. Everything here exists to serve that.
///
/// One item draws every readout, in the user's order.
@MainActor
public final class StatusItemController {

    public var onPrimaryAction: (() -> Void)?
    public var onSecondaryAction: (() -> Void)?
    public var onVisibilityChange: ((Bool) -> Void)?

    private let engine: MetricsEngine
    private let settings: SettingsStore
    private var hosted: [Hosted] = []
    private var layout: MenuBarItemLayout?
    /// The item the user last clicked. Everything anchored to "the status item" means
    /// this one, because with several of them the only sensible answer is the one the
    /// user just touched.
    private var activeItem: NSStatusItem?
    private var renderTask: Task<Void, Never>?
    private var lastReportedVisibility: Bool?

    /// One status item and the view drawing into it.
    private struct Hosted {
        let item: NSStatusItem
        let content: MenuBarContentView
    }

    public init(engine: MetricsEngine, settings: SettingsStore) {
        self.engine = engine
        self.settings = settings
    }

    // MARK: Installation

    public func install() {
        syncLayout()
        beginRendering()
        render()
    }

    public func remove() {
        renderTask?.cancel()
        renderTask = nil
        tearDownItems()
        layout = nil
    }

    /// The item keeps the name it has always had, so it stays where the user dragged it.
    static let combinedAutosaveName = "AirStatsStatusItem"

    /// Brings the installed item in line with the settings: in the bar, or out of it. A
    /// no-op unless that changed, so an unrelated settings write costs one comparison
    /// and no menu bar churn.
    private func syncLayout() {
        let desired = MenuBarItemLayout(settings: settings.settings.menuBar)
        guard desired != layout else { return }
        tearDownItems()
        layout = desired

        switch desired {
        case .combined:
            if let entry = makeItem(autosaveName: StatusItemController.combinedAutosaveName,
                                    label: "Bento Stats system statistics") {
                hosted = [entry]
            }

        case .hidden:
            break
        }
        reportVisibility()
    }

    private func makeItem(autosaveName: String, label: String) -> Hosted? {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = [.removalAllowed]
        item.autosaveName = autosaveName

        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return nil
        }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(label)

        let content = MenuBarContentView(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            content.topAnchor.constraint(equalTo: button.topAnchor),
            content.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        return Hosted(item: item, content: content)
    }

    /// Every item goes before the replacement set is reported. This avoids exposing a
    /// transient empty set while a layout rebuild is in progress.
    private func tearDownItems() {
        for entry in hosted {
            NSStatusBar.system.removeStatusItem(entry.item)
        }
        hosted.removeAll()
        activeItem = nil
    }

    // MARK: Geometry

    /// Screen-space rect of the status item button the panel should hang from, which is
    /// the one the user last clicked. Nil when the item is not currently on screen.
    public var anchorRect: NSRect? {
        guard let button = anchorItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    public var anchorScreen: NSScreen? {
        anchorItem?.button?.window?.screen ?? NSScreen.main
    }

    /// The last item clicked, or the first one when the panel is being opened by a hot
    /// key or a menu rather than by a click.
    private var anchorItem: NSStatusItem? {
        if let activeItem, hosted.contains(where: { $0.item === activeItem }) { return activeItem }
        return hosted.first?.item
    }

    public func presentMenu(_ menu: NSMenu) {
        guard let item = anchorItem else { return }
        item.menu = menu
        item.button?.performClick(nil)
        // Detach immediately so the next left-click goes back to our action.
        item.menu = nil
    }

    // MARK: Visibility

    /// `NSStatusItem.isVisible` is not a crowding signal: AppKit documents that it can
    /// remain true while the item is temporarily hidden for lack of menu bar space.
    /// Report only whether AirStats has installed status items. That is reliable for the
    /// explicit menu bar setting and avoids throttling from an unsupported inference.
    private func reportVisibility() {
        let visible = !hosted.isEmpty
        guard lastReportedVisibility != visible else { return }
        lastReportedVisibility = visible
        onVisibilityChange?(visible)
    }

    // MARK: Rendering

    /// Re-render whenever the engine publishes or settings change. Observation-driven
    /// rather than timer-driven: no snapshot, no redraw, no wakeup.
    private func beginRendering() {
        renderTask?.cancel()
        let changes = ObservedChanges { [engine, settings] in
            _ = engine.snapshot
            _ = settings.revision
        }
        renderTask = Task { @MainActor [weak self] in
            for await _ in changes {
                guard let self else { return }
                self.render()
            }
        }
    }

    private func render() {
        // Settings are read here rather than watched separately, so hiding or showing the
        // item takes effect on the same pass that redraws the numbers in it.
        syncLayout()
        guard !hosted.isEmpty else { return }
        let model = MenuBarRenderModel(snapshot: engine.snapshot,
                                       history: engine.history,
                                       settings: settings.settings,
                                       isStale: engine.isStale)
        for entry in hosted {
            entry.content.update(with: model)
            entry.item.length = entry.content.intrinsicContentSize.width
            entry.item.button?.setAccessibilityValue(model.accessibilityDescription)
        }
    }

    // MARK: Input

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        // Recorded before the action runs, because the action is what reads `anchorRect`
        // and the panel belongs under the item that was clicked.
        activeItem = hosted.first { $0.item.button === sender }?.item
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            onSecondaryAction?()
        } else {
            onPrimaryAction?()
        }
    }
}
