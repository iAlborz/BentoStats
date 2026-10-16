import AppKit
import ApplicationServices
import SwiftUI
import AirStatKit

/// Hosts the popover-style panel that opens from the status item.
///
/// An `NSPanel` rather than an `NSPopover`: a popover cannot be shown without
/// activating the app, cannot survive a Space change gracefully, and gives no
/// control over its own corner radius or material.
@MainActor
public final class PanelController: NSObject, NSWindowDelegate {

    public var onVisibilityChange: ((Bool) -> Void)?
    public var onRequestSettings: (() -> Void)?
    public var onRequestQuit: (() -> Void)?

    private let engine: MetricsEngine
    private let settings: SettingsStore
    /// Absent in the offscreen renderer. The panel's update row is drawn from it.
    private let updates: SoftwareUpdater?
    private var window: PanelWindow?
    private var layout: PanelLayoutState?
    private var isDisclosureTransitionActive = false
    /// Animations still running in the current disclosure: SwiftUI's reveal and
    /// AppKit's window resize. The transition ends when the last of them does.
    private var disclosureAnimationsPending = 0

    /// The window beside the panel that shows the hovered module's detail.
    private var detailWindow: PanelWindow?
    /// The row the pointer is over, with its frame in the panel.
    private var hoveredRow: (module: PanelModule, frame: CGRect)?
    /// The frame of the row whose detail is showing, which the detail lines up with.
    private var detailRowFrame: CGRect?
    private var isPointerInDetail = false
    /// The pointer's last position over a row, for telling a move towards the detail
    /// from a move onto another row.
    private var previousPointer: NSPoint?
    private var settleTask: Task<Void, Never>?
    private var hasPendingDetailResize = false
    /// Set while the detail is ordered out, so the key status it gives up on the way
    /// is not read as the user leaving the panel.
    private var isClosingDetail = false

    /// How long the detail holds before following the pointer elsewhere: long enough
    /// to cut across other rows on the way to it, short enough to read as a response.
    private static let detailGrace: Duration = .milliseconds(300)

    /// Every `NSEvent` monitor and notification observer this controller owns, in one
    /// place. Two collections, one lifetime: they are installed together when the
    /// panel appears and torn down together on every path that hides it.
    private var monitors: [Any] = []
    private var observers: [any NSObjectProtocol] = []

    /// Where the panel was last anchored, so it can re-anchor itself when its content
    /// changes height without being told again by the status item.
    private var lastAnchor: NSRect?
    private var lastScreen: NSScreen?

    /// Bumped on every show and hide so a fade-out that is still running cannot order
    /// out a panel the user has re-opened in the meantime.
    private var presentation: UInt64 = 0
    private var isPositioning = false

    /// Pending release of the hidden panel's view tree. See `scheduleWindowRelease`.
    private var releaseTask: Task<Void, Never>?

    /// How long a hidden panel keeps its window alive before the view tree is thrown
    /// away.
    ///
    /// The panel's SwiftUI graph costs 9.6 MB of dirty, non-reclaimable heap
    /// (`footprint`, MALLOC_SMALL, this machine) and an ordered-out window keeps every
    /// byte of it for the life of the process. Rebuilding costs 27 ms, which is far too
    /// much to pay on a panel the user opens every few minutes — so the window survives
    /// bursts of use and is only released once the panel has genuinely been left alone.
    private static let windowReleaseDelay: Duration = .seconds(120)

    public init(engine: MetricsEngine, settings: SettingsStore, updates: SoftwareUpdater? = nil) {
        self.engine = engine
        self.settings = settings
        self.updates = updates
        super.init()
    }

    public private(set) var isVisible = false {
        didSet {
            guard isVisible != oldValue else { return }
            onVisibilityChange?(isVisible)
        }
    }

    /// Live count of installed event monitors and observers.
    ///
    /// Monitor leaks are silent — nothing looks wrong until the app has forty stale
    /// global monitors — so the count is exposed for verification rather than left to
    /// be reasoned about.
    public var activeEventMonitorCount: Int { monitors.count + observers.count }

    // MARK: Presentation

    public func show(anchoredTo anchor: NSRect?, on screen: NSScreen?) {
        releaseTask?.cancel()
        releaseTask = nil
        let window = existingOrNewWindow()
        lastAnchor = anchor
        lastScreen = screen ?? anchor.flatMap(Self.screen(containing:))
        presentation &+= 1

        position(window, anchoredTo: anchor, on: lastScreen)
        window.alphaValue = 0
        // Ordering front "regardless" is what lets a menu bar app show a window while
        // another app stays active; `makeKeyAndOrderFront` would activate AirStat.
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = motionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        // Deliberately no `makeKey()`. Making a panel key programmatically activates
        // AirStat even when the panel is `.nonactivatingPanel` — measured, not assumed —
        // and the frontmost app loses focus the instant the user glances at their CPU
        // usage. The panel still *can* become key (`canBecomeKey` is true), so clicking
        // a control inside it hands it the keyboard without activating the app, which
        // is exactly what a non-activating panel is for.
        installDismissMonitors()
        isVisible = true
        WindowLog.log("panel shown frame=\(window.frame) key=\(window.isKeyWindow) appActive=\(NSApp.isActive) monitors=\(activeEventMonitorCount)")
    }

    public func hide() {
        // Unconditional: a monitor must never outlive the state that installed it,
        // even if this is called on a path where the panel was already hidden.
        removeDismissMonitors()
        hideDetail()
        hoveredRow = nil
        previousPointer = nil
        guard let window, isVisible else { return }
        presentation &+= 1
        let generation = presentation
        isVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = motionDuration * 0.7
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // The panel may have been re-opened during the fade; ordering it out
                // here would hide a window the user just asked for.
                guard let self, self.presentation == generation else { return }
                window.orderOut(nil)
            }
        }
        scheduleWindowRelease()
        WindowLog.log("panel hidden monitors=\(activeEventMonitorCount)")
    }

    /// Throw away a long-hidden panel's window, and with it the SwiftUI view tree.
    ///
    /// `orderOut` alone reclaims nothing: AppKit keeps every window that has not been
    /// *closed* in the application's window list, so a panel opened once at breakfast
    /// still holds its whole view graph at midnight.
    private func scheduleWindowRelease() {
        releaseTask?.cancel()
        releaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.windowReleaseDelay)
            guard !Task.isCancelled, let self, !self.isVisible, let window = self.window else { return }
            self.releaseTask = nil
            self.detailWindow?.delegate = nil
            self.detailWindow?.close()
            self.detailWindow = nil
            self.window = nil
            self.layout = nil
            self.lastAnchor = nil
            self.lastScreen = nil
            // Dropping the delegate first: `close` notifies it, and this controller has
            // nothing useful to do with a resize on a window it is discarding.
            window.delegate = nil
            window.close()
            WindowLog.log("panel window released after \(Self.windowReleaseDelay) hidden")
        }
    }

    public func reanchor(to anchor: NSRect?, on screen: NSScreen?) {
        guard let window, isVisible else { return }
        lastAnchor = anchor
        lastScreen = screen ?? anchor.flatMap(Self.screen(containing:))
        position(window, anchoredTo: anchor, on: lastScreen)
    }

    private var motionDuration: TimeInterval {
        Design.Motion.respectingAccessibility(Design.Motion.present) == nil ? 0 : 0.14
    }

    private func existingOrNewWindow() -> PanelWindow {
        if let window { return window }
        let layout = PanelLayoutState()
        layout.toggleModule = { [weak self] module in
            self?.toggleModule(module)
        }
        layout.rowHover = { [weak self] module, frame in
            self?.rowHover(module, frame: frame)
        }
        layout.detailHover = { [weak self] hovering in
            self?.detailHover(hovering)
        }
        let root = PanelRootView(engine: engine, settings: settings, updates: updates,
                                 layout: layout)
            .environment(\.panelActions, PanelActions(
                openSettings: { [weak self] in self?.onRequestSettings?() },
                quit: { [weak self] in self?.onRequestQuit?() },
                dismiss: { [weak self] in self?.hide() }
            ))
        // The window tracks its content's height, so collapsing a module or ejecting a
        // volume resizes the panel instead of clipping it or leaving a gap.
        let hosting = ContentSizedHostingView(rootView: root)
        hosting.onContentSizeChange = { [weak self] in self?.scheduleContentResize() }

        let window = PanelWindow(contentView: hosting)
        window.delegate = self
        // Escape is handled here as well as by the key monitor, so it still works if
        // the panel is key but the monitor is not installed.
        window.onCancel = { [weak self] in self?.hide() }

        let detailHosting = ContentSizedHostingView(
            rootView: PanelDetailView(engine: engine, settings: settings, layout: layout))
        detailHosting.onContentSizeChange = { [weak self] in self?.scheduleDetailResize() }
        let detailWindow = PanelWindow(contentView: detailHosting)
        detailWindow.title = "AirStats Detail"
        detailWindow.delegate = self
        detailWindow.onCancel = { [weak self] in self?.hide() }

        self.layout = layout
        self.window = window
        self.detailWindow = detailWindow
        return window
    }

    // MARK: Geometry

    /// Toggle one module as a single AppKit/SwiftUI transaction.
    ///
    /// SwiftUI's intrinsic height is an animation value, so following each invalidation
    /// makes the window chase the content one run-loop turn behind. Instead, stage the
    /// final hierarchy synchronously to obtain one destination, restore the current
    /// hierarchy before anything is displayed, then animate both systems to that one
    /// destination. Intrinsic callbacks and resize delegate re-entry are ignored until
    /// the transaction has completed.
    func toggleModule(_ module: PanelModule) {
        guard !isDisclosureTransitionActive else { return }

        let current = settings.settings.panel.collapsedModules
        let target = settings.settings.panel.collapsedModules(toggling: module)

        guard let window, isVisible, let layout else {
            settings.update { $0.panel.collapsedModules = target }
            return
        }

        isDisclosureTransitionActive = true

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        // Enter the transition on its own layout pass, before the hierarchy changes
        // shape. The scroll indicator is retired here, so the measurement below cannot
        // be the pass that flashes one.
        withTransaction(transaction) {
            layout.isDisclosureTransitionActive = true
            layout.disclosureOrigin = current
        }
        window.layoutIfNeeded()

        // Measure the final hierarchy without allowing the staging state to animate or
        // reach the screen. The window itself remains on its current frame throughout.
        withTransaction(transaction) {
            layout.collapsedModulesOverride = target
        }
        window.layoutIfNeeded()
        let fitting = window.contentView?.fittingSize
            ?? NSSize(width: PanelSettings.width, height: window.frame.height)
        let destination = targetFrame(for: fitting, anchoredTo: lastAnchor, on: lastScreen)

        let duration = disclosureDuration
        // Reduce Motion: nothing to animate, so the ordering is the whole job. The
        // hierarchy is already staged at its final shape, so the window is taken to the
        // frame that fits it before anything is drawn, and the setting is written
        // behind that. Nothing is ever laid out taller than the window holding it, and
        // implicit AppKit animations are off for the exchange, so neither the scroller
        // nor the backdrop has anything to fade.
        if duration == 0 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            window.setFrame(destination, display: false)
            settings.update { $0.panel.collapsedModules = target }
            withTransaction(transaction) {
                layout.collapsedModulesOverride = nil
                layout.disclosureOrigin = nil
                layout.isDisclosureTransitionActive = false
            }
            window.layoutIfNeeded()
            window.displayIfNeeded()
            CATransaction.commit()
            isDisclosureTransitionActive = false
            position(window, anchoredTo: lastAnchor, on: lastScreen)
            return
        }

        withTransaction(transaction) {
            layout.collapsedModulesOverride = current
        }
        window.layoutIfNeeded()

        // Persist behind the presentation override so this write cannot restructure the
        // visible tree before the coordinated transition begins.
        settings.update { $0.panel.collapsedModules = target }

        // The transition ends when the later of the two animations ends, not when
        // AppKit's does.
        //
        // The two are given the same curve and the same duration, but SwiftUI's starts
        // on its next render and AppKit's starts now, so the reveal is still a few
        // frames from done when the window arrives. Finishing on the window alone
        // measured the content while it was still short — 24pt short on a Memory open
        // — snapped the window down to that, and then let the resize path walk it back
        // up one intrinsic-size change at a time: seven visible steps after every
        // open. Waiting for both, the window sits at its destination while the reveal
        // catches up, and the one `position` at the end has nothing left to move.
        disclosureAnimationsPending = 2
        let animationDidEnd = { [weak self, weak window, weak layout] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.disclosureAnimationsPending -= 1
                guard self.disclosureAnimationsPending == 0, let window, let layout else { return }
                self.finishDisclosure(window: window, layout: layout)
            }
        }
        withAnimation(Design.Motion.disclosure, completionCriteria: .logicallyComplete) {
            layout.collapsedModulesOverride = target
        } completion: {
            animationDidEnd()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(destination, display: true)
        } completionHandler: {
            animationDidEnd()
        }
        // A completion that never comes would leave every click ignored and every
        // resize dropped for the life of the window. Neither has been seen to fail,
        // but the cost of being wrong is a dead panel, so the transition is ended by
        // the clock if it is still open well after both animations should be over.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 250))
            guard let self, self.isDisclosureTransitionActive,
                  self.disclosureAnimationsPending > 0,
                  let window = self.window, let layout = self.layout else { return }
            self.disclosureAnimationsPending = 0
            self.finishDisclosure(window: window, layout: layout)
        }
    }

    private var disclosureDuration: TimeInterval {
        Design.Motion.respectingAccessibility(Design.Motion.disclosure) == nil
            ? 0 : Design.Motion.disclosureDuration
    }

    private func finishDisclosure(window: NSWindow, layout: PanelLayoutState) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            layout.collapsedModulesOverride = nil
            layout.disclosureOrigin = nil
            layout.isDisclosureTransitionActive = false
        }
        isDisclosureTransitionActive = false
        // Resolve any sub-point discrepancy between the measured destination and the
        // final intrinsic size without producing a second visible move.
        position(window, anchoredTo: lastAnchor, on: lastScreen)
    }

    /// Anchor under the status item, nudged so the panel never hangs off the screen,
    /// slides under the menu bar, or grows past the bottom of the display.
    private func position(_ window: NSWindow, anchoredTo anchor: NSRect?, on screen: NSScreen?) {
        guard !isPositioning else { return }
        isPositioning = true
        defer { isPositioning = false }

        window.layoutIfNeeded()
        let fitting = window.contentView?.fittingSize
            ?? NSSize(width: PanelSettings.width, height: 400)

        let frame = targetFrame(for: fitting, anchoredTo: anchor, on: screen)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
        if detailWindow?.isVisible == true { positionDetail() }
    }

    private func targetFrame(for fitting: NSSize, anchoredTo anchor: NSRect?,
                             on screen: NSScreen?) -> NSRect {
        // The status item's own screen is the right one even when it is not the
        // primary: `visibleFrame` is in global coordinates, so a display whose menu
        // bar sits below or beside the primary's still resolves correctly.
        let targetScreen = screen
            ?? anchor.flatMap(Self.screen(containing:))
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = targetScreen?.visibleFrame else { return window?.frame ?? .zero }

        let margin = Design.Space.m
        let gap = Design.Space.s

        // Height is capped to the room actually below the status item. Without this a
        // panel with every module enabled runs off the bottom of a short display, and
        // the modules nearest the bottom become unreachable.
        let available = anchor.map { ($0.minY - gap) - (visible.minY + margin) }
            ?? (visible.height - margin * 2)
        // Whole points. A window cannot hold a half-point height, so a 568.5pt fit set
        // a 569pt frame that never compared equal to the frame asked for, and every
        // placement after it was a change that had to be applied again.
        let size = NSSize(width: fitting.width,
                          height: ceil(min(fitting.height, max(available, 160))))

        var x: CGFloat
        var y: CGFloat
        if let anchor {
            x = anchor.midX - size.width / 2
            y = anchor.minY - size.height - gap
        } else {
            // The status item is hidden — pushed off a crowded menu bar or behind the
            // notch. Fall back to the top trailing corner of its display, which is
            // where the item would have been.
            x = visible.maxX - size.width - margin
            y = visible.maxY - size.height - gap
        }

        // Keep fully on screen with a consistent margin, matching how macOS clamps
        // its own menu bar popovers.
        x = min(max(x, visible.minX + margin), max(visible.maxX - size.width - margin, visible.minX + margin))
        y = min(max(y, visible.minY + margin), max(visible.maxY - size.height - margin, visible.minY + margin))

        // One frame mutation, not two.
        //
        // This used to be `setContentSize` followed by `setFrameOrigin`. `setContentSize`
        // keeps the window's bottom-left origin and moves its top edge, which for a panel
        // pinned under the status item is the wrong edge entirely: the window grew upwards
        // into the menu bar and the origin call then dragged it back down. Two mutations
        // also meant two `windowDidResize` notifications, and that delegate re-enters this
        // method — `isPositioning` only guards the synchronous case, so the asynchronous
        // one came back a beat later and resized again. That second, late resize is what
        // read as a jitter.
        //
        // Setting the whole frame at once makes an unchanged placement a genuine no-op,
        // which is what stops the re-entrant pass from moving anything.
        return NSRect(x: x.rounded(), y: y.rounded(),
                      width: size.width, height: size.height)
    }

    private static func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    private static let escapeKeyCode: UInt16 = 53

    /// SwiftUI can invalidate its size several times in one layout pass, so the
    /// window is re-measured once on the next turn rather than on every invalidation.
    private func scheduleContentResize() {
        guard !isDisclosureTransitionActive else { return }
        guard !hasPendingResize else { return }
        hasPendingResize = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.hasPendingResize = false
            // A resize queued on the turn before a click would otherwise fire mid-
            // transition and snap the window to the destination unanimated.
            guard let window = self.window, self.isVisible,
                  !self.isDisclosureTransitionActive else { return }
            self.position(window, anchoredTo: self.lastAnchor, on: self.lastScreen)
        }
    }

    private var hasPendingResize = false

    /// SwiftUI grows the window downwards from its bottom-left corner; re-running the
    /// placement re-pins it under the status item and re-applies the height cap.
    public func windowDidResize(_ notification: Notification) {
        guard let window, notification.object as? NSWindow === window,
              isVisible, !isPositioning, !isDisclosureTransitionActive else { return }
        position(window, anchoredTo: lastAnchor, on: lastScreen)
    }

    /// Covers the dismissal the mouse monitor cannot see: ⌘-tabbing to another app.
    ///
    /// Either window can hold the keyboard — a click in the detail makes it key — so
    /// the panel goes only once neither does. Checked a turn later, because the window
    /// taking over is not key yet while the other one resigns.
    public func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        if let detailWindow, notification.object as? NSWindow === detailWindow,
           isClosingDetail || !detailWindow.isVisible { return }
        Task { @MainActor [weak self] in
            guard let self, self.isVisible,
                  self.window?.isKeyWindow != true,
                  self.detailWindow?.isKeyWindow != true else { return }
            WindowLog.log("panel resigned key; dismissing")
            self.hide()
        }
    }

    // MARK: Detail

    /// The pointer moving over a row, or leaving it (`frame` nil).
    private func rowHover(_ module: PanelModule, frame: CGRect?) {
        guard isVisible else { return }
        guard let frame else {
            if hoveredRow?.module == module { hoveredRow = nil }
            scheduleSettle()
            return
        }
        let pointer = NSEvent.mouseLocation
        defer { previousPointer = pointer }
        hoveredRow = (module, frame)

        if layout?.detailModule == module {
            settleTask?.cancel()
            // The row moved under the pointer: the list scrolled or reflowed.
            if detailRowFrame != frame {
                detailRowFrame = frame
                positionDetail()
            }
        } else if let previous = previousPointer, isHeadingToDetail(from: previous, to: pointer) {
            // Crossing other rows on the way to the open detail. Each move that keeps
            // heading there pushes the switch back; stopping short lets it happen.
            scheduleSettle()
        } else {
            settle()
        }
    }

    private func detailHover(_ hovering: Bool) {
        isPointerInDetail = hovering
        if hovering {
            settleTask?.cancel()
            // Coming back from the detail, the next row the pointer lands on is where
            // it is going, not a row it is passing over.
            previousPointer = nil
        } else {
            scheduleSettle()
        }
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.detailGrace)
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    /// Brings the detail in line with the pointer: over the detail it stays, over a row
    /// it shows that row's module, and anywhere else it closes.
    private func settle() {
        settleTask?.cancel()
        settleTask = nil
        guard isVisible, !isPointerInDetail else { return }
        if let row = hoveredRow {
            showDetail(row.module, rowFrame: row.frame)
        } else {
            hideDetail()
        }
    }

    /// Whether the move from `a` to `b` points into the open detail: `b` lies inside
    /// the triangle between `a` and the detail's near edge. This is how menus let the
    /// pointer cut diagonally across other items without each one taking over.
    private func isHeadingToDetail(from a: NSPoint, to b: NSPoint) -> Bool {
        guard a != b, let window, let detailWindow, detailWindow.isVisible else { return false }
        let detail = detailWindow.frame
        let edge = detail.midX < window.frame.midX ? detail.maxX : detail.minX
        let top = NSPoint(x: edge, y: detail.maxY)
        let bottom = NSPoint(x: edge, y: detail.minY)
        func side(_ p: NSPoint, _ q: NSPoint) -> CGFloat {
            (b.x - q.x) * (p.y - q.y) - (p.x - q.x) * (b.y - q.y)
        }
        let sides = [side(a, top), side(top, bottom), side(bottom, a)]
        return !(sides.contains { $0 < 0 } && sides.contains { $0 > 0 })
    }

    private func showDetail(_ module: PanelModule, rowFrame: CGRect) {
        guard let detailWindow, let layout else { return }
        layout.detailModule = module
        detailRowFrame = rowFrame
        positionDetail()
        if !detailWindow.isVisible { detailWindow.orderFrontRegardless() }
    }

    private func hideDetail() {
        settleTask?.cancel()
        settleTask = nil
        isPointerInDetail = false
        detailRowFrame = nil
        layout?.detailModule = nil
        guard let detailWindow, detailWindow.isVisible else { return }
        isClosingDetail = true
        detailWindow.orderOut(nil)
        isClosingDetail = false
    }

    /// Beside the panel, level with the row it belongs to. On the left by preference,
    /// since the panel hangs from the right-hand end of the menu bar; on the right
    /// when the left has no room.
    private func positionDetail() {
        guard let window, let detailWindow, let row = detailRowFrame,
              let visible = (window.screen ?? lastScreen ?? NSScreen.main)?.visibleFrame else { return }
        detailWindow.layoutIfNeeded()
        guard let fitting = detailWindow.contentView?.fittingSize, fitting.height > 0 else { return }

        let margin = Design.Space.m
        let gap = Design.Space.xs
        let panel = window.frame
        let height = ceil(min(fitting.height, visible.height - margin * 2))

        var x = panel.minX - gap - fitting.width
        if x < visible.minX + margin { x = panel.maxX + gap }
        x = min(x, visible.maxX - fitting.width - margin)
        // SwiftUI measures the row from the panel's top edge, and screen y runs upwards.
        // The detail's own top padding goes back on so its header sits level with the row.
        let rowTop = panel.maxY - row.minY + Design.Space.xs
        let y = min(max(rowTop - height, visible.minY + margin), visible.maxY - height - margin)

        let frame = NSRect(x: x.rounded(), y: y.rounded(), width: fitting.width, height: height)
        guard frame != detailWindow.frame else { return }
        detailWindow.setFrame(frame, display: true)
    }

    /// Like the panel, the detail is re-measured once on the next turn rather than on
    /// every invalidation.
    private func scheduleDetailResize() {
        guard !hasPendingDetailResize else { return }
        hasPendingDetailResize = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.hasPendingDetailResize = false
            guard self.detailWindow?.isVisible == true else { return }
            self.positionDetail()
        }
    }

    // MARK: Dismissal

    private func installDismissMonitors() {
        removeDismissMonitors()

        // The local monitor covers the case where the panel has taken the keyboard; the
        // global one covers the far more common case where it has not, and only exists
        // when the app is already trusted for accessibility — this never prompts for a
        // permission.
        if let escape = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            Task { @MainActor in self?.hide() }
            return nil
        }) {
            monitors.append(escape)
        }
        if AXIsProcessTrusted(),
           let escape = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
               guard event.keyCode == Self.escapeKeyCode else { return }
               Task { @MainActor in self?.hide() }
           }) {
            monitors.append(escape)
        }

        // Global monitors see only events destined for *other* apps, so a click inside
        // the panel never reaches this and cannot dismiss it.
        //
        // A click on the status item can, though: since macOS 27 the menu bar is drawn
        // by the window server, and the item's mouse-down reaches this monitor too.
        // Dismissing here let the item's own action, which runs on mouse-up, find the
        // panel closed and reopen it, so the item could never close the panel. A plain
        // click there belongs to the item's action, so it is left alone here; a right-
        // or Control-click opens the item's menu, which should still close the panel.
        if let outside = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] event in
                let location = event.locationInWindow
                let isPlainClick = event.type == .leftMouseDown
                    && !event.modifierFlags.contains(.control)
                Task { @MainActor in
                    guard let self else { return }
                    if isPlainClick, let anchor = self.lastAnchor, anchor.contains(location) { return }
                    WindowLog.log("click outside the panel; dismissing")
                    self.hide()
                }
            }) {
            monitors.append(outside)
        }

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    WindowLog.log("active space changed; dismissing panel")
                    self?.hide()
                }
        })

        WindowLog.log("panel monitors installed count=\(activeEventMonitorCount)")
    }

    private func removeDismissMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }
}

/// Borderless, non-activating panel on a solid backdrop.
final class PanelWindow: NSPanel {

    /// The panel's backdrop: black in dark appearance, Apple's light grey in light.
    ///
    /// Solid rather than translucent glass: the wallpaper and the sheen showing through
    /// made the panel hard to read.
    static let backdropColor = NSColor(name: nil) { appearance in
        appearance.isDark ? .black : NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1)
    }

    var onCancel: (() -> Void)?

    init(contentView: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isRestorable = false
        // `close()` is how the controller reclaims the view tree, and the default here
        // is to have the window release itself when that happens — which, on a window
        // ARC already owns through `PanelController.window`, is an over-release.
        isReleasedWhenClosed = false
        // Follow the user across Spaces and appear over full-screen apps, the way
        // the system's own menu bar extras do.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = false
        title = "AirStats Panel"

        let backdrop = PanelBackdropView()
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Design.Radius.panel
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true

        contentView.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: backdrop.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])

        self.contentView = backdrop
    }

    /// Borderless windows are not key by default, which would break text fields
    /// and keyboard navigation inside the panel. Becoming key does not activate the
    /// app: that is exactly what `.nonactivatingPanel` buys.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The responder-chain half of Escape-to-dismiss, for when the key window is the
    /// panel but focus sits on a control that swallows the key event.
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Paints `PanelWindow.backdropColor` into its layer. A layer holds a resolved colour,
/// so it is set again in `updateLayer`, which AppKit calls with the view's appearance
/// current whenever that appearance changes.
private final class PanelBackdropView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = PanelWindow.backdropColor.cgColor
    }
}

// MARK: - Actions plumbed through the environment

/// Not `Sendable`: every action targets the main actor by construction, and the
/// environment only ever carries it between main-actor views.
public struct PanelActions {
    public var openSettings: @MainActor () -> Void
    public var quit: @MainActor () -> Void
    public var dismiss: @MainActor () -> Void

    public init(openSettings: @escaping @MainActor () -> Void = {},
                quit: @escaping @MainActor () -> Void = {},
                dismiss: @escaping @MainActor () -> Void = {}) {
        self.openSettings = openSettings
        self.quit = quit
        self.dismiss = dismiss
    }
}

private struct PanelActionsKey: EnvironmentKey {
    static let defaultValue = PanelActions()
}

extension EnvironmentValues {
    public var panelActions: PanelActions {
        get { self[PanelActionsKey.self] }
        set { self[PanelActionsKey.self] = newValue }
    }
}
