import SwiftUI
import AppKit
import Observation
import AirStatKit

/// Ephemeral presentation state shared by the panel's SwiftUI trees and its AppKit
/// controller: which module's detail is open beside the panel, the hooks the rows and
/// the detail report the pointer through, and, for the original style, the override
/// that exists only long enough to measure and animate one disclosure as a coordinated
/// transaction. Settings remain the durable truth.
@MainActor
@Observable
final class PanelLayoutState {
    /// The module whose detail is showing beside the panel, nil while none is.
    var detailModule: PanelModule?
    /// The pointer over a row or card, with its frame in the panel; nil once it has left.
    @ObservationIgnored var rowHover: ((PanelModule, CGRect?) -> Void)?
    @ObservationIgnored var detailHover: ((Bool) -> Void)?

    /// The bento grid is being arranged: cards move, resize, come and go.
    var isEditing = false
    /// Closes the detail beside the panel as editing starts.
    @ObservationIgnored var onBeginEditing: (() -> Void)?

    func beginEditing() {
        onBeginEditing?()
        isEditing = true
    }

    var collapsedModulesOverride: Set<PanelModule>?
    /// The collapsed set a disclosure started from, held until it has finished.
    var disclosureOrigin: Set<PanelModule>?
    var isDisclosureTransitionActive = false
    @ObservationIgnored var toggleModule: ((PanelModule) -> Void)?
}

/// Root of the click-down panel.
///
/// The modules, as a list of rows or a grid of cards depending on the panel style, over
/// a footer. The panel sizes to its content and has no chrome of its own; it scrolls
/// only in the one case where it would otherwise run off the screen.
public struct PanelRootView: View {

    private let engine: MetricsEngine
    private let settings: SettingsStore
    /// Absent in the offscreen renderer, which has no Sparkle to ask.
    private let updates: SoftwareUpdater?
    /// Absent in renderers and previews, where disclosure writes settings directly.
    private let layout: PanelLayoutState?

    public init(engine: MetricsEngine, settings: SettingsStore, updates: SoftwareUpdater? = nil) {
        self.engine = engine
        self.settings = settings
        self.updates = updates
        self.layout = nil
    }

    init(engine: MetricsEngine, settings: SettingsStore, updates: SoftwareUpdater?,
         layout: PanelLayoutState) {
        self.engine = engine
        self.settings = settings
        self.updates = updates
        self.layout = layout
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pending = updates?.pending {
                PanelUpdateRow(update: pending) { [updates] in
                    // Sparkle's window is a window, and the panel closes when it loses
                    // key, so it would take the update with it on the way out.
                    actions.dismiss()
                    updates?.installPending()
                }
                PanelSeparator()
            }
            ScrollView(.vertical) {
                if style == .bento {
                    BentoGrid(engine: engine, settings: settings, layout: layout)
                } else if style == .macbook {
                    MacBookView(engine: engine, settings: settings, layout: layout)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        let captionColumnWidth = captionColumnWidth
                        ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                            if style == .original, index > 0 {
                                PanelSeparator(isVisible: separatorNeeded(before: index))
                            }
                            PanelModuleView(module: module, engine: engine, settings: settings,
                                            layout: layout,
                                            presentation: style == .original ? .accordion : .row,
                                            captionColumnWidth: captionColumnWidth)
                        }
                    }
                    .padding(.vertical, Design.Space.xs)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // No indicator, ever.
            //
            // The window is sized to this list, so in the ordinary case there is
            // nothing to scroll and nothing for an indicator to report. What it does
            // instead is flicker: every change in content height leaves one layout pass
            // in which the list is taller than the window that has not yet grown to
            // hold it, and the scroll view spends that pass showing a scroller. Under
            // `Show scroll bars: Always` that scroller is a legacy one, so it also
            // takes real width and reflows the text beneath it on the way in and out.
            // `.never` rather than `.automatic`, because `.hidden` still defers to that
            // setting. The list stays scrollable by trackpad and wheel for the rare
            // case that it reaches the ceiling below.
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
            // Bento carries Settings and Quit as cards of its own.
            if style != .bento {
                PanelSeparator()
                PanelFooterView()
            }
        }
        // The list takes whatever height the window has, and the rows sit at its top.
        //
        // The window's frame and this hierarchy's height animate as two systems, and
        // for the frames where they disagree something has to give. It used to be the
        // list: sized to its content and capped by a `frame(maxHeight:)`, it was
        // centred in the room the window offered, so every row slid down by half the
        // difference while the window led and back up as the content caught up. The
        // header being clicked moved under the pointer. Letting the scroll view fill
        // the window instead keeps every row where it is; the disagreement lands on
        // the footer, which rides the window's bottom edge, and on a few points of
        // list clipped behind it while the content leads.
        //
        // Sizing: the window is measured from this hierarchy's ideal height, which for
        // a scroll view is its content, so below the screen's ceiling nothing scrolls.
        // Past it the controller caps the window and the list scrolls under a footer
        // that stays on screen.
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(width: style == .bento ? BentoGrid.width : style == .macbook ? MacBookView.width
                                                                          : PanelSettings.width)
        .environment(\.metricFormatter, MetricFormatter(settings: settings.settings.general))
    }

    @Environment(\.panelActions) private var actions

    private var modules: [PanelModule] { settings.settings.panel.visibleModules }

    private var style: PanelStyle { settings.settings.panel.style }

    /// One width for every row's qualifier column, from the captions on screen now.
    /// A list row drawn as a meter shows no caption, so it takes no part.
    private var captionColumnWidth: CGFloat {
        let formatter = MetricFormatter(settings: settings.settings.general)
        return PanelSummary.captionColumnWidth(for: modules.map {
            PanelSummary.make(for: $0, engine: engine, formatter: formatter)
        }.filter { style == .original || $0.fraction == nil })
    }

    /// In the original style, a rule earns its place only where it delimits a block of
    /// detail.
    ///
    /// Drawing one between every module turned the panel into a ruled table — nine
    /// full-width lines competing with the content they were meant to organise. Between
    /// two collapsed summary rows there is nothing to divide: the rows already read as a
    /// list. So a separator appears only where an expanded module begins or ends, which
    /// is exactly where the eye needs to know a block started.
    ///
    /// While a disclosure runs, a rule the new layout adds stays clear until the module
    /// it belongs to has finished unfolding, so it never cuts across a half-open detail.
    /// Rules the new layout drops fade with the fold as before.
    private func separatorNeeded(before index: Int) -> Bool {
        let collapsed = layout?.collapsedModulesOverride
            ?? settings.settings.panel.collapsedModules
        guard let origin = layout?.disclosureOrigin else {
            return separatorNeeded(before: index, collapsed: collapsed)
        }
        return separatorNeeded(before: index, collapsed: collapsed)
            && separatorNeeded(before: index, collapsed: origin)
    }

    private func separatorNeeded(before index: Int, collapsed: Set<PanelModule>) -> Bool {
        !collapsed.contains(modules[index - 1]) || !collapsed.contains(modules[index])
    }

}

/// The detail of the module whose row is hovered, in its own window beside the panel.
struct PanelDetailView: View {
    let engine: MetricsEngine
    let settings: SettingsStore
    let layout: PanelLayoutState

    var body: some View {
        if let module = layout.detailModule {
            Group {
                if settings.settings.panel.style.usesCardDetail {
                    BentoDetail(module: module, engine: engine, settings: settings)
                } else {
                    let formatter = MetricFormatter(settings: settings.settings.general)
                    let summary = PanelSummary.make(for: module, engine: engine, formatter: formatter)
                    PanelModuleView(module: module, engine: engine, settings: settings,
                                    presentation: .detail,
                                    captionColumnWidth: PanelSummary.captionColumnWidth(for: [summary]))
                        .padding(.vertical, Design.Space.xs)
                        .frame(width: PanelSettings.width)
                }
            }
            // A fresh view per module, so a chart range picked for one module does
            // not carry over to the next.
            .id(module)
            .contentShape(Rectangle())
            .onHover { layout.detailHover?($0) }
        }
    }
}

/// Inset rule between modules. macOS insets its separators to the content margin so
/// they read as dividing the text, not as slicing the window in half.
///
/// A rule that is not wanted turns clear rather than disappearing. It reads identically
/// — a transparent hairline is nothing — but it costs the layout the same one point
/// whatever the modules around it are doing. Inserting and removing the view instead
/// meant a single toggle restructured the stack twice, because `separatorNeeded` looks
/// at both of a rule's neighbours: expanding a module flipped the rule above it and the
/// rule below it. Only the first module escaped, its leading rule being suppressed by
/// the `index > 0` test, which is exactly why every module except CPU jumped harder.
struct PanelSeparator: View {
    var isVisible = true

    var body: some View {
        Rectangle()
            .fill(isVisible ? Design.Palette.separator : .clear)
            .frame(height: Design.Space.hairline)
            .padding(.horizontal, Design.Space.panelInset)
            .accessibilityHidden(true)
    }
}

/// The whole of what a scheduled update does to the app until the user asks for more.
///
/// It sits above the modules rather than in the footer because it is news and the footer
/// is furniture, and it is one row rather than a banner because an update is not more
/// important than the readings the user opened the panel to see.
struct PanelUpdateRow: View {
    let update: PendingUpdate
    let install: @MainActor () -> Void

    /// A staged update wants a relaunch and nothing else, so the row says so instead
    /// of promising an install it has already done.
    private var headline: String {
        update.isReadyToInstall ? "AirStats \(update.version) is ready" : "AirStats \(update.version) is available"
    }

    private var action: String { update.isReadyToInstall ? "Restart" : "Install" }

    @State private var isHovering = false

    var body: some View {
        Button(action: install) {
            HStack(spacing: Design.Space.s) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(Design.Text.label)
                    .foregroundStyle(Design.Palette.accent)
                Text(headline)
                    .font(Design.Text.label)
                    .foregroundStyle(Design.Palette.primaryText)
                Spacer(minLength: Design.Space.m)
                Text(action)
                    .font(Design.Text.caption)
                    .foregroundStyle(Design.Palette.accent)
            }
            .padding(.horizontal, Design.Space.panelInset)
            .padding(.vertical, Design.Space.m)
            .background(isHovering ? Design.Palette.track : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Design.Motion.respectingAccessibility(Design.Motion.hover)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(headline)
        .accessibilityHint(update.isReadyToInstall ? "Relaunches AirStats into the new version"
                                                   : "Opens the updater to install it")
    }
}

struct PanelFooterView: View {
    @Environment(\.panelActions) private var actions

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            PanelFooterButton(title: "Settings…", symbol: "gearshape", action: actions.openSettings)
                .keyboardShortcut(",", modifiers: .command)
            Spacer(minLength: Design.Space.m)
            PanelFooterButton(title: "Quit", symbol: "power", action: actions.quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, Design.Space.s)
        .padding(.vertical, Design.Space.xs)
    }
}

/// A footer control styled like a macOS menu item rather than a hyperlink: the whole
/// row highlights on hover, and the hit target is the highlight.
struct PanelFooterButton: View {
    let title: String
    let symbol: String
    let action: @MainActor () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.s) {
                Image(systemName: symbol)
                    .font(Design.Text.caption)
                    .foregroundStyle(Design.Palette.secondaryText)
                Text(title)
                    .font(Design.Text.label)
                    .foregroundStyle(Design.Palette.primaryText)
            }
            .padding(.horizontal, Design.Space.m)
            .padding(.vertical, Design.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(isHovering ? Design.Palette.track : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Design.Motion.respectingAccessibility(Design.Motion.hover)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(title)
    }
}
