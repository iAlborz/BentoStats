import SwiftUI
import AppKit
import AirStatKit

struct MenuBarPane: View {
    let settings: SettingsStore
    let engine: MetricsEngine?

    @State private var dropTarget: MenuBarItemConfig.ID?
    /// The preview's own, so dragging over the bar does not also light up the list.
    @State private var previewDropTarget: MenuBarItemConfig.ID?

    private var items: [MenuBarItemConfig] { settings.settings.menuBar.items }

    private var availability: MetricAvailability {
        MetricAvailability(snapshot: SettingsPreview.snapshot(engine))
    }

    var body: some View {
        Form {
            Section {
                MenuBarPreviewStrip(model: previewModel, isEmpty: previewModel.items.isEmpty) { slot in
                    previewReadout(slot)
                } accessory: {
                    AddReadoutButton { addMenuItems }
                }
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Preview")
            } footer: {
                SettingsFootnote(String(localized: "Click a readout to choose its style or remove it. Drag one to move it."))
            }

            Section {
                readoutList
                readoutListControls
            } header: {
                Text("Readouts")
            }
        }
        .settingsFormStyle()
    }

    // MARK: Readout list

    private var readoutList: some View {
        SettingsListBox {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                SettingsListRow(isFirst: index == 0,
                                isDropTarget: item.id == dropTarget) {
                    readoutRow(item, index: index)
                }
                .draggable(item.id.uuidString) {
                    Text(item.metric.label).padding(Design.Space.xs)
                }
                .dropDestination(for: String.self) { payload, _ in
                    dropTarget = nil
                    guard let dragged = payload.first else { return false }
                    return move(idString: dragged, to: index)
                } isTargeted: { targeted in
                    dropTarget = targeted ? item.id : (dropTarget == item.id ? nil : dropTarget)
                }
            }
        }
        .accessibilityLabel("Menu bar readouts")
    }

    /// Everything a readout has, on the readout's own row.
    ///
    /// The metric and style used to live in an "Editing …" section below the list,
    /// reached by selecting a row. That put the control you wanted somewhere other
    /// than the thing you wanted to change — and once the list ran past four readouts
    /// the section fell below the fold, so clicking a row appeared to do nothing at
    /// all. The style also sat in the row already, right-aligned exactly where a popup
    /// menu's value sits, as text that did not respond to a click.
    private func readoutRow(_ item: MenuBarItemConfig, index: Int) -> some View {
        HStack(spacing: Design.Space.m) {
            Toggle("", isOn: enabledBinding(for: item))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(isLastEnabled(item))
                .help(isLastEnabled(item)
                      ? "At least one readout must stay visible so the menu bar item remains clickable."
                      : "Show \(item.metric.label) in the menu bar")
                .accessibilityLabel("Show \(item.metric.label)")

            RowMenu(title: item.metric.label,
                    width: Self.metricColumn,
                    label: String(localized: "\(item.metric.label) metric")) {
                Picker("Metric", selection: metricBinding(for: item)) {
                    ForEach(MenuBarMetric.allCases, id: \.self) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.inline)
            }

            Spacer(minLength: Design.Space.s)

            // The badge stands in for the style control rather than joining it: a
            // readout this Mac cannot serve has no style worth choosing, and the two
            // together do not fit the row.
            if let reason = availability.note(for: item.metric) {
                UnavailableBadge(reason: reason)
            } else {
                styleMenu(item)
            }

            ReorderControls(canMoveUp: index > 0,
                            canMoveDown: index < items.count - 1,
                            itemLabel: item.metric.label) { offset in
                move(item, by: offset)
            }

            // Deleting belongs on the row it deletes. As a button under the list it
            // acted on "the selected readout", and the only thing naming that readout
            // was a tint on one row — a destructive control whose target you had to
            // infer. It also matches the desktop widget's module list, which is the same
            // list of the same metrics doing the same job.
            RowIconButton(systemName: "trash",
                          help: items.count <= 1
                              ? String(localized: "The last readout cannot be removed.")
                              : String(localized: "Remove \(item.metric.label) from the menu bar"),
                          label: String(localized: "Remove \(item.metric.label)")) {
                remove(item)
            }
            .disabled(items.count <= 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.metric.label)
        .accessibilityValue("\(item.isEnabled ? String(localized: "Shown") : String(localized: "Hidden")), \(item.style.label) style")
    }

    /// The style popup, carrying the caption toggle with it.
    ///
    /// The caption is a property of the style — only three of the five can show one —
    /// so it belongs behind the same control rather than as a second checkbox
    /// competing with the one that means "shown".
    private func styleMenu(_ item: MenuBarItemConfig) -> some View {
        RowMenu(title: item.style.label,
                label: String(localized: "\(item.metric.label) display style")) {
            Picker("Display as", selection: styleBinding(for: item)) {
                ForEach(item.metric.supportedStyles, id: \.self) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.inline)

            if item.style.supportsCaption {
                Divider()
                Toggle(captionToggleTitle(for: item), isOn: captionBinding(for: item))
            }
        }
    }

    /// Wide enough for "Battery Time Remaining", the longest metric name. The style
    /// beside it needs no column: it is the last thing in the row and sits against the
    /// trailing edge, where a fixed box would only add a gap.
    private static let metricColumn: CGFloat = 175

    private var readoutListControls: some View {
        HStack(spacing: Design.Space.m) {
            Menu {
                addMenuItems
            } label: {
                Label("Add Readout", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Add a readout")

            Spacer()
        }
    }

    /// Every metric, shared by the list's Add Readout and the preview's plus.
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
        if let index = items.firstIndex(where: { $0.id == slot.id }) {
            let item = items[index]
            PreviewReadout(item: item, isDropTarget: previewDropTarget == item.id) {
                readoutMenu(item)
            }
            .draggable(item.id.uuidString) {
                Text(item.metric.label).padding(Design.Space.xs)
            }
            .dropDestination(for: String.self) { payload, _ in
                previewDropTarget = nil
                guard let dragged = payload.first else { return false }
                return move(idString: dragged, to: index)
            } isTargeted: { targeted in
                previewDropTarget = targeted ? item.id : (previewDropTarget == item.id ? nil : previewDropTarget)
            }
        }
    }

    /// The readout's styles, each drawn as it would sit in the menu bar, then Remove.
    private func readoutMenu(_ item: MenuBarItemConfig) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: item.metric.label))
        for style in item.metric.supportedStyles {
            let entry = ActionMenuItem(title: style.label) {
                styleBinding(for: item).wrappedValue = style
            }
            entry.state = style == item.style ? .on : .off
            entry.image = sample(of: item, as: style)
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
    private func sample(of item: MenuBarItemConfig, as style: MenuBarDisplayStyle) -> NSImage {
        var config = item
        config.style = style
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

    /// The label the menu bar would draw for this readout, quoted back so the toggle
    /// says what it will actually put on screen, and where: a bar stacks its caption
    /// beside it, the rest put it above the number.
    private func captionToggleTitle(for item: MenuBarItemConfig) -> String {
        if item.style == .bar {
            let label = MenuBarRenderModel.sideCaptionText(for: item.metric) ?? item.metric.label
            return String(localized: "Show \"\(label)\" beside the bar")
        }
        if item.style == .tile {
            let label = MenuBarRenderModel.sideCaptionText(for: item.metric) ?? item.metric.label
            return String(localized: "Show \"\(label)\" inside the tile")
        }
        let label = MenuBarRenderModel.captionText(for: item.metric) ?? item.metric.label
        return String(localized: "Show \"\(label)\" above the value")
    }

    // MARK: Model access

    /// Bindings carry the item's id rather than its position, so a rename or reorder
    /// cannot silently write to whichever readout now sits at that index.
    ///
    /// The getters answer from the captured item instead of going back to the array.
    /// SwiftUI reads a `Picker`'s selection during the same update pass that replaces
    /// the list, before the pane's body has had a chance to drop the editing section,
    /// so a getter that subscripted by index would trap on anything that shortens
    /// `menuBar.items` under the editor: Restore Defaults, or an import. The metric,
    /// style and caption factories are internal rather than private so the regression
    /// test can hold a binding across exactly that reset.
    private func mutate(_ item: MenuBarItemConfig,
                        _ body: @escaping (inout MenuBarItemConfig) -> Void) {
        settings.update { s in
            guard let index = s.menuBar.items.firstIndex(where: { $0.id == item.id }) else { return }
            body(&s.menuBar.items[index])
        }
    }

    private func enabledBinding(for item: MenuBarItemConfig) -> Binding<Bool> {
        Binding(get: { item.isEnabled },
                set: { isOn in mutate(item) { $0.isEnabled = isOn } })
    }

    func metricBinding(for item: MenuBarItemConfig) -> Binding<MenuBarMetric> {
        Binding(get: { item.metric },
                set: { metric in
                    mutate(item) { config in
                        config.metric = metric
                        // `sanitized()` in the store will clamp an unsupported style,
                        // but doing it here keeps the picker from flashing a value it
                        // is about to lose.
                        if !metric.supportedStyles.contains(config.style) {
                            config.style = metric.supportedStyles.first ?? .text
                        }
                    }
                })
    }

    func styleBinding(for item: MenuBarItemConfig) -> Binding<MenuBarDisplayStyle> {
        Binding(get: { item.style },
                set: { style in mutate(item) { $0.style = style } })
    }

    func captionBinding(for item: MenuBarItemConfig) -> Binding<Bool> {
        Binding(get: { item.showsCaption },
                set: { shows in mutate(item) { $0.showsCaption = shows } })
    }

    /// The item the store would refuse to disable, or nil when more than one is on.
    private var lastEnabledItem: MenuBarItemConfig? {
        let enabled = items.filter(\.isEnabled)
        return enabled.count == 1 ? enabled.first : nil
    }

    private func isLastEnabled(_ item: MenuBarItemConfig) -> Bool {
        lastEnabledItem?.id == item.id
    }

    /// Drop handler. Returns false for a payload that is not one of our rows, so a
    /// stray drag from another app is refused rather than silently ignored.
    private func move(idString: String, to destination: Int) -> Bool {
        guard let id = UUID(uuidString: idString),
              let source = items.firstIndex(where: { $0.id == id }),
              source != destination else { return false }
        settings.update { s in
            guard s.menuBar.items.indices.contains(source),
                  s.menuBar.items.indices.contains(destination) else { return }
            let moved = s.menuBar.items.remove(at: source)
            s.menuBar.items.insert(moved, at: destination)
        }
        return true
    }

    private func move(_ item: MenuBarItemConfig, by offset: Int) {
        settings.update { s in
            guard let index = s.menuBar.items.firstIndex(where: { $0.id == item.id }) else { return }
            let target = index + offset
            guard s.menuBar.items.indices.contains(target) else { return }
            s.menuBar.items.swapAt(index, target)
        }
    }

    private func add(_ metric: MenuBarMetric) {
        let config = MenuBarItemConfig(metric: metric,
                                       style: metric.supportedStyles.first ?? .text)
        settings.update { $0.menuBar.items.append(config) }
    }

    /// Removed by identity rather than by position, for the same reason the row's
    /// bindings are: the row a user pressed is the row that goes, whatever the array
    /// has done since.
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
        MenuBarRenderModel(snapshot: SettingsPreview.snapshot(engine),
                           history: SettingsPreview.history(engine),
                           settings: settings.settings,
                           // Never stale-dimmed. This preview answers "what will my
                           // menu bar look like", and greying it because the last
                           // sample is a few seconds old would read as the setting
                           // being broken. The real menu bar still dims.
                           isStale: false)
    }
}

/// One readout in the preview, highlighted the way the menu bar highlights an item:
/// faintly under the pointer, more while its menu is open.
///
/// The menu is AppKit's, popped on click. A SwiftUI `Menu` opens on mouse-down, so the
/// readout under it could never be dragged.
private struct PreviewReadout: View {
    let item: MenuBarItemConfig
    let isDropTarget: Bool
    let menu: () -> NSMenu

    @State private var isHovering = false
    @State private var isMenuOpen = false
    @State private var anchor = MenuAnchor()

    var body: some View {
        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
            .fill(Design.Palette.primaryText.opacity(isMenuOpen ? 0.16 : isHovering ? 0.08 : 0))
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .strokeBorder(Design.Palette.accent, lineWidth: 2)
                }
            }
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? Design.Palette.primaryText : Design.Palette.secondaryText)
                .frame(width: 22, height: 22)
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
