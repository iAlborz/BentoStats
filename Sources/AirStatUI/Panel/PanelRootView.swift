import SwiftUI
import AppKit
import Observation
import AirStatKit

/// Ephemeral presentation state shared by the panel's SwiftUI trees and its AppKit
/// controller: which module's detail is open beside the panel, the hooks the cards and
/// the detail report the pointer through, and whether the cards are being arranged.
/// Settings remain the durable truth.
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
}

/// Root of the click-down panel: the cards, drawn the way the picked layout draws them.
///
/// The panel sizes to its content and has no chrome of its own; it scrolls only in the
/// one case where it would otherwise run off the screen.
public struct PanelRootView: View {

    private let engine: MetricsEngine
    private let settings: SettingsStore
    /// Absent in renderers and previews, which neither edit the cards nor open details.
    private let layout: PanelLayoutState?
    /// Absent unless this copy updates itself.
    private let updater: Updater?

    public init(engine: MetricsEngine, settings: SettingsStore) {
        self.engine = engine
        self.settings = settings
        self.layout = nil
        self.updater = nil
    }

    init(engine: MetricsEngine, settings: SettingsStore, layout: PanelLayoutState,
         updater: Updater? = nil) {
        self.engine = engine
        self.settings = settings
        self.layout = layout
        self.updater = updater
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let updater { UpdateBanner(updater: updater) }
            ScrollView(.vertical) {
                switch style {
                case .bento:
                    BentoGrid(engine: engine, settings: settings, layout: layout)
                case .bentoSmall:
                    BentoGrid(engine: engine, settings: settings, layout: layout, arrangement: .small)
                case .macbook:
                    MacBookView(engine: engine, settings: settings, layout: layout)
                case .debug:
                    BentoGallery(engine: engine, settings: settings, layout: layout)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // No indicator, ever.
            //
            // The window is sized to this content, so in the ordinary case there is
            // nothing to scroll and nothing for an indicator to report. What it does
            // instead is flicker: every change in content height leaves one layout pass
            // in which the content is taller than the window that has not yet grown to
            // hold it, and the scroll view spends that pass showing a scroller. Under
            // `Show scroll bars: Always` that scroller is a legacy one, so it also
            // takes real width and reflows the content beneath it on the way in and out.
            // `.never` rather than `.automatic`, because `.hidden` still defers to that
            // setting. The content stays scrollable by trackpad and wheel for the rare
            // case that it reaches the ceiling below.
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
            // The bento layouts carry Settings and Quit as cards of their own.
            if style == .macbook || style == .debug {
                PanelSeparator()
                PanelFooterView()
            }
        }
        // The content takes whatever height the window has, and sits at its top, so
        // when the window and the content disagree for a frame while either resizes,
        // the content stays put and the difference lands on the footer.
        //
        // Sizing: the window is measured from this hierarchy's ideal height, which for
        // a scroll view is its content, so below the screen's ceiling nothing scrolls.
        // Past it the controller caps the window and the content scrolls.
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(width: width)
        .environment(\.metricFormatter, MetricFormatter(settings: settings.settings.general))
    }

    private var style: PanelStyle { settings.settings.panel.style }

    private var width: CGFloat {
        switch style {
        case .bento, .debug: return BentoGrid.width(for: .regular)
        case .bentoSmall: return BentoGrid.width(for: .small)
        case .macbook: return MacBookView.width
        }
    }
}

/// The detail of the card under the pointer, in its own window beside the panel.
struct PanelDetailView: View {
    let engine: MetricsEngine
    let settings: SettingsStore
    let layout: PanelLayoutState

    var body: some View {
        if let module = layout.detailModule {
            BentoDetail(module: module, engine: engine, settings: settings)
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

struct PanelFooterView: View {
    @Environment(\.panelActions) private var actions

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            PanelFooterButton(title: String(localized: "Settings…"), symbol: "gearshape", action: actions.openSettings)
                .keyboardShortcut(",", modifiers: .command)
            Spacer(minLength: Design.Space.m)
            PanelFooterButton(title: String(localized: "Quit"), symbol: "power", action: actions.quit)
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
