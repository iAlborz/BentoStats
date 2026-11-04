import SwiftUI
import AppKit
import AirStatKit

/// The menu bar, edited where it is drawn: click a readout for its styles, drag it to
/// move it, and add one with the plus. A section of General, since this is all the menu
/// bar has to set.
struct MenuBarPreviewSection: View {
    let settings: SettingsStore
    let engine: MetricsEngine?

    /// The readout being dragged, from the moment it is picked up.
    @State private var dragged: MenuBarItemConfig.ID?
    /// The order the bar would have if the dragged readout were dropped where it is,
    /// which the preview shows in the meantime. Nil while nothing is over the bar.
    @State private var draft: [MenuBarItemConfig]?

    private var items: [MenuBarItemConfig] { draft ?? settings.settings.menuBar.items }

    private var availability: MetricAvailability {
        MetricAvailability(snapshot: SettingsPreview.snapshot(engine))
    }

    var body: some View {
        Section {
            MenuBarPreviewStrip(model: previewModel, isEmpty: previewModel.items.isEmpty,
                                dragged: dragged, onDrag: drag) { slot in
                previewReadout(slot)
            } accessory: {
                AddReadoutButton { addMenuItems }
            }
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Menu Bar")
        } footer: {
            SettingsFootnote(String(localized: "Click a readout to choose its style or remove it. Drag one to move it."))
        }
    }

    /// The bar rearranges itself as a readout is dragged across it, so where it will go
    /// is where it already is. Each place is worked out from the stored order, not the
    /// draft, so the drag never compounds on itself; leaving the bar puts it back.
    private func drag(_ event: MenuBarPreviewDrag) {
        guard let dragged else { return }
        switch event {
        case .over(let place):
            let moved = Self.moving(dragged, to: place, in: settings.settings.menuBar.items)
            if moved != draft { draft = moved }
        case .left:
            draft = nil
        case .dropped(let place):
            settings.update { $0.menuBar.items = Self.moving(dragged, to: place, in: $0.menuBar.items) }
            draft = nil
            self.dragged = nil
        }
    }

    /// `items` with the readout `id` moved to `place` among the other readouts the bar
    /// shows. A hidden one keeps its spot among the rest. Internal for the test.
    static func moving(_ id: MenuBarItemConfig.ID, to place: Int,
                       in items: [MenuBarItemConfig]) -> [MenuBarItemConfig] {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return items }
        var result = items
        let item = result.remove(at: from)
        let shown = result.indices.filter { result[$0].isEnabled }
        let at = place < shown.count ? shown[place] : (shown.last.map { $0 + 1 } ?? result.count)
        result.insert(item, at: at)
        return result
    }

    /// Every metric, for the plus.
    private var addMenuItems: some View {
        ForEach(MenuBarMetric.allCases, id: \.self) { metric in
            Button {
                add(metric)
            } label: {
                // Still selectable: a settings file travels between Macs, and
                // a readout this machine cannot serve may work on the next.
                Text(availability.note(for: metric) == nil
                     ? metric.label
                     : String(localized: "\(metric.label) (unavailable here)"))
            }
        }
    }

    // MARK: Preview editing

    /// A readout in the preview, as a control: click it for its styles, drag it to move it.
    @ViewBuilder
    private func previewReadout(_ slot: MenuBarPreviewSlot) -> some View {
        if let item = items.first(where: { $0.id == slot.id }) {
            PreviewReadout(item: item, isDragged: dragged == item.id && draft != nil) {
                readoutMenu(item)
            }
            .onDrag {
                dragged = item.id
                return NSItemProvider(object: item.id.uuidString as NSString)
            } preview: {
                dragPreview(item)
            }
        }
    }

    /// The readout itself under the pointer, at the preview's size.
    private func dragPreview(_ item: MenuBarItemConfig) -> some View {
        let image = sample(of: item, as: Choice(style: item.style, showsCaption: item.showsCaption,
                                                title: item.style.label))
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: image.size.width * MenuBarPreview.scale,
                   height: image.size.height * MenuBarPreview.scale)
            .padding(Design.Space.xs)
            .background(Color.black.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
    }

    /// One entry in a readout's menu: a style, and whether it carries its caption.
    private struct Choice {
        let style: MenuBarDisplayStyle
        let showsCaption: Bool
        let title: String
    }

    /// Each style once, keeping the readout's caption as it is. A number that names
    /// itself offers its graph twice, with its caption and without.
    private func choices(for item: MenuBarItemConfig) -> [Choice] {
        item.metric.supportedStyles.flatMap { style -> [Choice] in
            guard item.metric.namesItself, style == .graph else {
                return [Choice(style: style, showsCaption: item.showsCaption, title: style.label)]
            }
            return [Choice(style: .graph, showsCaption: true, title: style.label),
                    Choice(style: .graph, showsCaption: false, title: String(localized: "Graph Only"))]
        }
    }

    /// The readout's styles, each drawn as it would sit in the menu bar, then Remove.
    private func readoutMenu(_ item: MenuBarItemConfig) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: item.metric.label))
        for choice in choices(for: item) {
            let entry = ActionMenuItem(title: choice.title) {
                choose(choice.style, showsCaption: choice.showsCaption, for: item)
            }
            entry.state = choice.style == item.style && choice.showsCaption == item.showsCaption ? .on : .off
            entry.image = sample(of: item, as: choice)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let remove = ActionMenuItem(title: String(localized: "Remove")) { self.remove(item) }
        if isLastEnabled(item) {
            remove.isEnabled = false
            remove.toolTip = String(localized: "At least one readout must stay visible so the menu bar item remains clickable.")
        }
        menu.addItem(remove)
        return menu
    }

    /// The readout drawn in one style, with the same numbers the preview has, so the
    /// menu shows what each style looks like rather than only naming it. Drawn when the
    /// menu draws it, at the menu's own scale and in its appearance.
    private func sample(of item: MenuBarItemConfig, as choice: Choice) -> NSImage {
        var config = item
        config.style = choice.style
        config.showsCaption = choice.showsCaption
        var sampled = settings.settings
        sampled.menuBar.items = [config]
        let view = MenuBarContentView(frame: .zero)
        view.update(with: MenuBarRenderModel(snapshot: SettingsPreview.snapshot(engine),
                                             history: SettingsPreview.history(engine),
                                             settings: sampled,
                                             isStale: false))
        let size = view.intrinsicContentSize
        view.frame.size = size
        return NSImage(size: size, flipped: false) { rect in
            view.draw(rect)
            return true
        }
    }

    // MARK: Model access

    /// Writes find the item by its id rather than its position, so a reorder cannot
    /// silently write to whichever readout now sits at that index, and a menu still open
    /// after something shortened `menuBar.items` — Restore Defaults, or an import —
    /// writes nothing rather than trapping.
    private func mutate(_ item: MenuBarItemConfig,
                        _ body: @escaping (inout MenuBarItemConfig) -> Void) {
        settings.update { s in
            guard let index = s.menuBar.items.firstIndex(where: { $0.id == item.id }) else { return }
            body(&s.menuBar.items[index])
        }
    }

    /// What a menu entry does. Internal so the regression tests can call it across a
    /// reset and a reorder.
    func choose(_ style: MenuBarDisplayStyle, showsCaption: Bool, for item: MenuBarItemConfig) {
        mutate(item) {
            $0.style = style
            $0.showsCaption = showsCaption
        }
    }

    /// The item the store would refuse to disable, or nil when more than one is on.
    private var lastEnabledItem: MenuBarItemConfig? {
        let enabled = items.filter(\.isEnabled)
        return enabled.count == 1 ? enabled.first : nil
    }

    private func isLastEnabled(_ item: MenuBarItemConfig) -> Bool {
        lastEnabledItem?.id == item.id
    }

    /// Appended after the last readout, where the plus is. A readout hidden from the
    /// list this used to have is not drawn anywhere now, so adding its metric brings
    /// that one back, in its own style, rather than a second copy beside it. Internal
    /// for the test.
    func add(_ metric: MenuBarMetric) {
        settings.update { s in
            if let hidden = s.menuBar.items.firstIndex(where: { $0.metric == metric && !$0.isEnabled }) {
                var item = s.menuBar.items.remove(at: hidden)
                item.isEnabled = true
                s.menuBar.items.append(item)
            } else {
                s.menuBar.items.append(MenuBarItemConfig(metric: metric,
                                                         style: metric.supportedStyles.first ?? .text))
            }
        }
    }

    /// Removed by identity rather than by position, for the same reason the menu's
    /// choices are: the readout a user clicked is the one that goes, whatever the array has
    /// done since.
    private func remove(_ item: MenuBarItemConfig) {
        settings.update { s in
            guard s.menuBar.items.count > 1 else { return }
            s.menuBar.items.removeAll { $0.id == item.id }
        }
    }

    // MARK: Preview model

    /// Built from live data when the app is running and from fixtures when it is
    /// not, but through the same model either way — the preview never invents a
    /// value, it renders whatever the metric actually reports.
    private var previewModel: MenuBarRenderModel {
        var shown = settings.settings
        shown.menuBar.items = items
        return MenuBarRenderModel(snapshot: SettingsPreview.snapshot(engine),
                                  history: SettingsPreview.history(engine),
                                  settings: shown,
                                  // Never stale-dimmed. This preview answers "what will my
                                  // menu bar look like", and greying it because the last
                                  // sample is a few seconds old would read as the setting
                                  // being broken. The real menu bar still dims.
                                  isStale: false)
    }
}

/// One readout in the preview, highlighted the way the menu bar highlights an item:
/// faintly under the pointer, more while its menu is open or it is being moved.
///
/// The menu is AppKit's, popped on click. A SwiftUI `Menu` opens on mouse-down, so the
/// readout under it could never be dragged.
private struct PreviewReadout: View {
    let item: MenuBarItemConfig
    let isDragged: Bool
    let menu: () -> NSMenu

    @State private var isHovering = false
    @State private var isMenuOpen = false
    @State private var anchor = MenuAnchor()

    var body: some View {
        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
            .fill(Design.Palette.primaryText.opacity(isMenuOpen || isDragged ? 0.16 : isHovering ? 0.08 : 0))
            .contentShape(Rectangle())
            .background(MenuAnchorView(anchor: anchor))
            .onHover { hovering in
                withAnimation(Design.Motion.hover) { isHovering = hovering }
            }
            .onTapGesture(perform: open)
            .help(item.metric.label)
            .accessibilityElement()
            .accessibilityLabel(item.metric.label)
            .accessibilityValue(item.style.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
    }

    /// The menu tracks in a loop of its own until it closes, so it opens a turn later,
    /// once the highlight has drawn.
    private func open() {
        isMenuOpen = true
        DispatchQueue.main.async {
            anchor.popUp(menu())
            isMenuOpen = false
        }
    }
}

/// The plus after the readouts: every metric, one click away from the bar it goes in.
private struct AddReadoutButton<Items: View>: View {
    @ViewBuilder let items: () -> Items

    @State private var isHovering = false

    var body: some View {
        Menu {
            items()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11 * MenuBarPreview.scale, weight: .semibold))
                .foregroundStyle(isHovering ? Design.Palette.primaryText : Design.Palette.secondaryText)
                .frame(width: 22 * MenuBarPreview.scale, height: 22 * MenuBarPreview.scale)
                .background {
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .fill(Design.Palette.primaryText.opacity(isHovering ? 0.10 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: Design.Radius.control,
                                               style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            withAnimation(Design.Motion.hover) { isHovering = hovering }
        }
        .help("Add a readout")
        .accessibilityLabel("Add a readout")
    }
}

/// The view an AppKit menu pops up under: the one SwiftUI laid out behind a readout.
@MainActor
private final class MenuAnchor {
    weak var view: NSView?

    func popUp(_ menu: NSMenu) {
        guard let view else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }

    /// Flipped, so "under it" is its height down. Never hit: the clicks belong to the
    /// SwiftUI view in front.
    private final class AnchorView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A menu item that runs a closure, for menus built in code.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

    @objc private func run() { handler() }
}
