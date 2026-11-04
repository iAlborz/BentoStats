import AppKit
import SwiftUI
import AirStatKit

/// Standard document-less preferences window.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {

    private let engine: MetricsEngine
    private let settings: SettingsStore
    /// Shared with the threshold monitor, so the notifications pane reports the same
    /// grant the alerts actually depend on rather than a second opinion.
    private let authority: NotificationAuthority?
    private let updater: Updater?
    private var window: NSWindow?

    public init(engine: MetricsEngine, settings: SettingsStore,
                authority: NotificationAuthority? = nil, updater: Updater? = nil) {
        self.engine = engine
        self.settings = settings
        self.authority = authority
        self.updater = updater
        super.init()
    }

    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // A menu bar app is an accessory; it must activate explicitly or the
        // settings window opens behind whatever the user was doing.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    /// Panes of forms, chart galleries and colour wells cost 12.6 MB of dirty,
    /// non-reclaimable heap (`footprint`, MALLOC_SMALL, this machine) once they have
    /// been built. Settings is opened rarely and closed for the rest of the session, so
    /// keeping that resident until quit is the worst of both worlds — the window is
    /// discarded on close and rebuilt on the next `show`.
    public func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow()
        let root = SettingsRootView(settings: settings, engine: engine,
                                    authority: authority, updater: updater) { [weak window] tab in
            window?.title = tab.label
        }
        window.delegate = self
        window.title = String(localized: "Bento Stats Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false

        // The click-down panel's black, so the two surfaces read as one app rather than
        // as a floating panel and a stock preferences window. The content paints it.
        //
        // The window is non-opaque with no fill of its own, so nothing squares the
        // corners off: the frame view only rounds and masks the content while the window
        // draws itself normally. So the rounding comes from the backdrop's own layer —
        // which is exactly how `PanelWindow` gets its corners.
        window.titlebarAppearsTransparent = true
        // The pane's name is in the source list next to it, selected. Repeating it in
        // a titlebar the panel does not have is the one thing that would still say
        // "settings window".
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear

        let backdrop = NSView()
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Design.Radius.window
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: backdrop.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])
        window.contentView = backdrop

        window.setContentSize(SettingsRootView.windowSize)
        window.setFrameAutosaveName("AirStatsSettingsWindow")
        return window
    }
}

/// The settings window's content: a source list of panes beside the selected one,
/// which is the shape macOS System Settings uses.
struct SettingsRootView: View {
    let settings: SettingsStore
    let engine: MetricsEngine?
    /// Nil in the offscreen renderer: `UNUserNotificationCenter` traps outside an app bundle.
    let authority: NotificationAuthority?
    /// Absent unless this copy updates itself.
    let updater: Updater?
    /// Lets the window title follow the selected pane, which is what System
    /// Settings does and what `navigationTitle` used to give us for free.
    var onPaneChange: ((SettingsTab) -> Void)?

    @State private var tab: SettingsTab

    /// Fixed rather than resizable, so the offscreen renderer measures the same
    /// window the user gets. Each pane scrolls its own form.
    ///
    /// Taller than the 560 it was: the content view now runs under the titlebar, and
    /// the strip the traffic lights sit in is height the panes used to have.
    static let windowSize = NSSize(width: 760, height: 588)

    /// Clearance for the traffic lights, which float over the content now that the
    /// titlebar draws nothing. Content starts below it rather than scrolling under it:
    /// a form row sliding behind three buttons is worse than a band of plain glass.
    private static let titlebarInset: CGFloat = 28

    init(settings: SettingsStore, engine: MetricsEngine? = nil,
         authority: NotificationAuthority? = nil, updater: Updater? = nil,
         initialTab: SettingsTab? = nil, onPaneChange: ((SettingsTab) -> Void)? = nil) {
        self.settings = settings
        self.engine = engine
        self.authority = authority
        self.updater = updater
        self.onPaneChange = onPaneChange
        _tab = State(initialValue: initialTab ?? SettingsTab.renderDefault)
    }

    var body: some View {
        // No rule between the columns: the cards are what sets the list apart, on the
        // panel's black, as they are in the panel.
        HStack(spacing: 0) {
            sidebar
                .frame(width: SettingsRootView.sidebarWidth)
            VStack(spacing: 0) {
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                paneFooter
            }
        }
        .padding(.top, SettingsRootView.titlebarInset)
        .frame(width: windowWidth, height: windowHeight)
        // Painted here rather than by the window, so the offscreen render shows it too.
        .background(Color(nsColor: PanelWindow.backdropColor))
        .onAppear { onPaneChange?(tab) }
        .onChange(of: tab) { _, newValue in
            onPaneChange?(newValue)
        }
    }

    /// Laid out by hand rather than with `NavigationSplitView`, which drew an opaque
    /// black 0.5pt rule between the columns — measured `#000000` at the seam in both
    /// appearances, in the real window as well as the render.
    ///
    /// The panes are square cards, the panel's own: its surface on its black, at its
    /// radius, the selected one ringed the way an open card is. Each is its icon alone;
    /// the name is in the tooltip and in what VoiceOver reads. Buttons rather than a
    /// `List`: every card stays keyboard-focusable, and the source list survives
    /// offscreen rendering, which an `NSTableView` does not.
    private var sidebar: some View {
        ScrollView {
            VStack(spacing: Design.Space.m) {
                // The window's title bar is transparent and carries no title, so the
                // mark is what says whose settings these are. Small and in the tertiary
                // tint: this labels the list, it is not the top of it.
                LogoMark(size: 16)
                    .foregroundStyle(Design.Palette.tertiaryText)
                    .padding(.bottom, Design.Space.xs)

                ForEach(SettingsTab.allCases) { item in
                    paneCard(item)
                }
            }
            .padding(SettingsRootView.sidebarInset)
        }
        .accessibilityLabel("Settings sections")
    }

    private func paneCard(_ item: SettingsTab) -> some View {
        let isSelected = item == tab
        let shape = RoundedRectangle(cornerRadius: Design.Radius.tile, style: .continuous)
        return Button {
            tab = item
        } label: {
            Image(systemName: item.symbolName)
                .font(.system(size: 26))
                .foregroundStyle(isSelected ? Design.Palette.accent : Design.Palette.secondaryText)
                .frame(width: SettingsRootView.cardSide, height: SettingsRootView.cardSide)
                .background(shape.fill(BentoGrid.surface))
            .overlay {
                if isSelected { shape.strokeBorder(Design.Palette.accent, lineWidth: 2) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(item.label)
        // A Button already publishes its label subtree as one element, so naming it
        // here is all it takes to announce "General, selected, button" instead of
        // walking into the card's decoration.
        //
        // Not `.accessibilityElement(children: .ignore)`, which reads the same but
        // builds a replacement element in place of the button and so carries no press
        // action. The rows still announced themselves as buttons, because a trait is a
        // description and not an action, and nothing happened when VoiceOver activated
        // them.
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Show \(item.label) settings")
    }

    private var windowWidth: CGFloat { SettingsRootView.windowSize.width }
    private var windowHeight: CGFloat { SettingsRootView.windowSize.height }
    private static let cardSide: CGFloat = 72
    private static let sidebarInset: CGFloat = Design.Space.l
    private static let sidebarWidth: CGFloat = cardSide + 2 * sidebarInset

    @ViewBuilder
    private var pane: some View {
        switch tab {
        case .general: GeneralPane(settings: settings, engine: engine, updater: updater)
        case .notifications: NotificationsPane(settings: settings, engine: engine,
                                               authority: authority)
        case .about: AboutPane(settings: settings)
        }
    }

    /// One bar under every pane, carrying that pane's restore-defaults.
    ///
    /// It was a section at the bottom of each pane's form, which put a destructive
    /// control in a different place on every pane — and always behind a scroll, since
    /// it is by definition the last thing. As a bar it is in one place, reachable
    /// without scrolling, and outside the form, which is the right register for a
    /// control that acts on the form rather than being part of it.
    @ViewBuilder
    private var paneFooter: some View {
        if !tab.sections.isEmpty {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Design.Palette.separator)
                    .frame(height: Design.Space.hairline)
                    .accessibilityHidden(true)
                HStack {
                    Spacer()
                    RestoreDefaultsButton(settings: settings,
                                          sections: tab.sections,
                                          title: tab.label)
                }
                .padding(.horizontal, Design.Space.l)
                .padding(.vertical, Design.Space.s)
            }
        }
    }
}
