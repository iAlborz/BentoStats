import SwiftUI
import AppKit
import AirStatKit

/// The bento style: every module as a card in a grid of mixed sizes, the way Apple lays
/// out what is new in a Mac.
///
/// The grid is square cells, six across, and every card spans a whole number of them:
/// 1×1, 2×1, 1×2, 2×2, 3×2, 2×3 or 4×2. The cards are the user's to arrange, the way
/// Control Center's controls are. Pressing and holding a card, or right-clicking one,
/// puts the grid into edit mode: a card is dragged to move it and by its corner to
/// resize it, the minus removes it, the bar underneath adds more, and each card's menu
/// picks its size and how it draws itself, as its object, a big number or a chart. See
/// `BentoLayout` for how the cards pack. The arrangement it starts with, and goes back to
/// on Reset:
///
///     ┌─────────┬─────────┬─────────┐
///     │         │         │   SSD   │
///     │   CPU   │ Memory  ├─────────┤
///     │         │         │ Battery │
///     ├─────────┼─────────┼────┬────┤
///     │         │  Wi-Fi  │    │ ⚙︎  │
///     │   GPU   ├─────────┤Temp├────┤
///     │         │ System  │    │ ⏻  │
///     └─────────┴─────────┴────┴────┘
///
/// At those sizes the cards draw as they were designed: the CPU and Memory cards each
/// carry the processes that answer their question, the busiest under the chip and the
/// biggest under the module, so processes have no card of their own. At any other size
/// or style a card is put together from the same parts: its object, its reading, the
/// readings that support it, and its history.
///
/// Each card follows Apple's: one object or one big number in the middle, set in the
/// card's own colour, and a short caption under it, on plain white cards over light
/// grey (or dark cards over black). No title bars, borders or shadows.
///
/// Hovering a card opens the same detail beside the panel that a list row does. Built
/// from shapes, never a `Canvas`: see `PlotShape` for why.
struct BentoGrid: View {
    let engine: MetricsEngine
    let settings: SettingsStore
    let layout: PanelLayoutState?
    /// Cards to draw in place of the user's arrangement, which cannot then be edited:
    /// the debug layout's gallery.
    var showing: [BentoTile]? = nil
    /// Marks each card with its size, for the gallery.
    var labelsSizes = false

    private static let inset: CGFloat = 12
    private static let gap: CGFloat = 10
    /// One square cell. Six across, with the gaps and the inset, is 734 wide.
    private static let cell: CGFloat = 110
    static let width = inset * 2 + span(BentoLayout.columns)
    private static let space = "bento"

    /// The length of `cells` cells and the gaps between them, across or down.
    private static func span(_ cells: Int) -> CGFloat {
        cell * CGFloat(cells) + gap * CGFloat(cells - 1)
    }

    private static func frame(of placement: BentoPlacement) -> CGRect {
        CGRect(x: CGFloat(placement.column) * (cell + gap), y: CGFloat(placement.row) * (cell + gap),
               width: span(placement.columns), height: span(placement.rows))
    }

    @Environment(\.panelActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The arrangement while a card is being dragged or resized. It goes to the settings
    /// when the card is let go, so a drag is one write rather than one per card it passes.
    @State private var working: [BentoTile]?
    @State private var drag: TileDrag?
    @State private var resizeStart: BentoTileSize?
    @State private var jiggle = false
    /// Set while a card is held by its body or its corner, and cleared however the
    /// gesture ends. A resize can end in cancellation rather than release, the card
    /// changing size under the pointer, and a cancelled gesture never reaches `onEnded`.
    @GestureState private var isMoving = false
    @GestureState private var isResizing = false

    private struct TileDrag {
        let id: UUID
        /// Where the card was when the drag began, and where it is now.
        let start: CGPoint
        var origin: CGPoint
        /// The card it last traded places with, and where the pointer was then, so one
        /// trade cannot set off another while the pointer stands still.
        var lastTarget: UUID?
        var lastSwap: CGPoint
    }

    private var formatter: MetricFormatter {
        MetricFormatter(settings: settings.settings.general)
    }

    private var tiles: [BentoTile] { working ?? showing ?? settings.settings.panel.bentoTiles }
    /// The arrangement can be changed: in the panel, and not in the gallery.
    private var canEdit: Bool { layout != nil && showing == nil }
    private var isEditing: Bool { layout?.isEditing == true }

    var body: some View {
        let tiles = self.tiles
        let packed = BentoLayout.pack(tiles)
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                    if let placement = packed.placements[tile.id] {
                        placed(tile, frame: Self.frame(of: placement), index: index)
                    }
                }
            }
            .frame(width: Self.span(BentoLayout.columns), height: Self.span(max(packed.rows, 1)),
                   alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
            .padding(Self.inset)
            if isEditing {
                editBar
                    .padding(.horizontal, Self.inset)
                    .padding(.bottom, Self.inset)
            }
        }
        .animation(Design.Motion.respectingAccessibility(.spring(duration: 0.3, bounce: 0.12)), value: tiles)
        .environment(\.metricFormatter, formatter)
        .onChange(of: isMoving) { _, moving in
            guard !moving else { return }
            withAnimation(Design.Motion.respectingAccessibility(.spring(duration: 0.3, bounce: 0.12))) {
                drag = nil
            }
            commit()
        }
        .onChange(of: isResizing) { _, resizing in
            guard !resizing else { return }
            resizeStart = nil
            commit()
        }
        .onChange(of: isEditing, initial: true) { _, editing in
            if !editing { commit() }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { jiggle = false }
            guard editing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) { jiggle = true }
        }
    }

    // MARK: Arranging

    /// A card at its place in the grid, or under the pointer while it is dragged, with
    /// the edit controls over it in edit mode.
    @ViewBuilder
    private func placed(_ tile: BentoTile, frame: CGRect, index: Int) -> some View {
        let isDragged = drag?.id == tile.id
        let origin = isDragged ? drag?.origin ?? frame.origin : frame.origin
        // Neighbours lean opposite ways, so the grid shimmers rather than sways.
        let tilt = (index.isMultiple(of: 2) ? 1.0 : -1.0) * (jiggle ? 0.6 : -0.6)
        tileView(tile, size: frame.size)
            .frame(width: frame.width, height: frame.height)
            .allowsHitTesting(!isEditing)
            .overlay {
                if isEditing { editControls(tile, frame: frame) }
            }
            .overlay(alignment: .bottomLeading) {
                if labelsSizes {
                    Text(tile.size.label)
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(nsColor: .systemPurple)))
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .contextMenu {
                if !isEditing, canEdit {
                    Button("Edit Layout", systemImage: "square.grid.2x2") { layout?.beginEditing() }
                }
            }
            // Pressing and holding a module card starts arranging, as in Control Center.
            // Not an action card: holding Quit must not quit on the way.
            .gesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in layout?.beginEditing() },
                     including: isEditing || tile.kind.isAction || !canEdit ? .subviews : .all)
            .rotationEffect(.degrees(isEditing && !isDragged ? tilt : 0))
            .scaleEffect(isDragged ? 1.04 : 1)
            .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 12, y: 4)
            .zIndex(isDragged ? 1 : 0)
            .offset(x: origin.x, y: origin.y)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    /// Over a card in edit mode: the surface it is dragged by, the minus that removes it,
    /// the menu for its size and style, and the corner it is resized by.
    private func editControls(_ tile: BentoTile, frame: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(moveGesture(tile, frame: frame))
            .overlay(alignment: .topLeading) {
                // Settings and Quit stay: without them the panel has no way out.
                if !tile.kind.isAction {
                    badge("minus", label: "Remove \(tile.kind.label)") {
                        edit { $0.removeAll { $0.id == tile.id } }
                    }
                    .offset(x: -7, y: -7)
                }
            }
            .overlay(alignment: .topTrailing) {
                // Inside the corner: outside, it would meet the next card's minus.
                options(tile).padding(Design.Space.s)
            }
            .overlay(alignment: .bottomTrailing) {
                resizeHandle(tile)
            }
    }

    private func moveGesture(_ tile: BentoTile, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .updating($isMoving) { _, moving, _ in moving = true }
            .onChanged { value in
                if drag == nil {
                    working = tiles
                    drag = TileDrag(id: tile.id, start: frame.origin, origin: frame.origin,
                                    lastTarget: nil, lastSwap: value.startLocation)
                }
                guard let start = drag?.start else { return }
                drag?.origin = CGPoint(x: start.x + value.translation.width,
                                       y: start.y + value.translation.height)
                reorder(tile.id, toward: value.location)
            }
    }

    /// Moves the dragged card to the place of the card under the pointer, and the cards
    /// between them along by one, the way a list reorders.
    private func reorder(_ id: UUID, toward point: CGPoint) {
        guard var list = working, let drag else { return }
        let packed = BentoLayout.pack(list).placements
        guard let target = list.first(where: { tile in
            tile.id != id && packed[tile.id].map { Self.frame(of: $0).contains(point) } == true
        }) else {
            self.drag?.lastTarget = nil
            return
        }
        guard target.id != drag.lastTarget,
              hypot(point.x - drag.lastSwap.x, point.y - drag.lastSwap.y) > 12,
              let from = list.firstIndex(where: { $0.id == id }),
              let to = list.firstIndex(where: { $0.id == target.id }) else { return }
        list.insert(list.remove(at: from), at: to)
        working = list
        self.drag?.lastTarget = target.id
        self.drag?.lastSwap = point
    }

    /// The corner a card is resized by: dragged, it snaps to the nearest size the card
    /// can take, and the cards around it flow out of the way.
    private func resizeHandle(_ tile: BentoTile) -> some View {
        ResizeCorner()
            .stroke(Design.Palette.secondaryText, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 14, height: 14)
            .padding(7)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .updating($isResizing) { _, resizing, _ in resizing = true }
                    .onChanged { value in
                        if resizeStart == nil {
                            resizeStart = tile.size
                            working = tiles
                        }
                        guard let start = resizeStart else { return }
                        let pitch = Self.cell + Self.gap
                        let columns = Int(((Self.span(start.columns) + value.translation.width + Self.gap) / pitch).rounded())
                        let rows = Int(((Self.span(start.rows) + value.translation.height + Self.gap) / pitch).rounded())
                        guard let size = BentoTileSize.nearest(columns: max(columns, 1), rows: max(rows, 1),
                                                               in: tile.kind.sizes),
                              let index = working?.firstIndex(where: { $0.id == tile.id }),
                              working?[index].size != size else { return }
                        working?[index].size = size
                    }
            )
            .accessibilityLabel("Resize \(tile.kind.label)")
    }

    /// A card's size, and for a module card how it draws itself.
    private func options(_ tile: BentoTile) -> some View {
        Menu {
            if !tile.kind.styles(for: tile.size).isEmpty {
                Picker("Style", selection: binding(tile.id, \.style, default: tile.style)) {
                    ForEach(tile.kind.styles(for: tile.size), id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
            Picker("Size", selection: binding(tile.id, \.size, default: tile.size)) {
                ForEach(tile.kind.sizes, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            badgeFace("ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("\(tile.kind.label) options")
    }

    private func binding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<BentoTile, Value>,
                                default fallback: Value) -> Binding<Value> {
        Binding {
            tiles.first { $0.id == id }?[keyPath: keyPath] ?? fallback
        } set: { value in
            edit { list in
                if let index = list.firstIndex(where: { $0.id == id }) { list[index][keyPath: keyPath] = value }
            }
        }
    }

    private func badge(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { badgeFace(symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func badgeFace(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Design.Palette.primaryText)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Self.badgeFill))
            .overlay(Circle().strokeBorder(Design.Palette.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .contentShape(Circle())
    }

    private static let badgeFill = Color(nsColor: NSColor(name: nil) {
        $0.isDark ? NSColor(white: 0.32, alpha: 1) : NSColor(white: 0.9, alpha: 1)
    })

    /// Under the grid in edit mode: add a card, go back to the designed arrangement, done.
    private var editBar: some View {
        HStack(spacing: Design.Space.m) {
            Menu {
                ForEach(BentoTileKind.allCases, id: \.self) { kind in
                    Button(kind.label, systemImage: kind.symbolName) {
                        edit { $0.append(BentoTile(kind: kind)) }
                    }
                }
            } label: {
                pill("plus", "Add Card")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            Button { edit { $0 = BentoLayout.defaultTiles } } label: {
                pill("arrow.counterclockwise", "Reset")
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Text("Drag to move · Drag a corner to resize")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Design.Palette.tertiaryText)
            Spacer(minLength: 0)
            Button { layout?.isEditing = false } label: {
                pill(nil, "Done", isProminent: true)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func pill(_ symbol: String?, _ title: String, isProminent: Bool = false) -> some View {
        HStack(spacing: Design.Space.xs) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            }
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(isProminent ? Color.white : Design.Palette.primaryText)
        .padding(.horizontal, Design.Space.l)
        .padding(.vertical, Design.Space.s)
        .background(Capsule().fill(isProminent ? AnyShapeStyle(Design.Palette.accent)
                                               : AnyShapeStyle(BentoCard<EmptyView>.surface)))
        .contentShape(Capsule())
    }

    /// A change to the arrangement, saved and animated.
    private func edit(_ change: (inout [BentoTile]) -> Void) {
        var list = settings.settings.panel.bentoTiles
        change(&list)
        let sanitized = BentoLayout.sanitized(list)
        settings.update { $0.panel.bentoTiles = sanitized }
    }

    private func commit() {
        guard let working else { return }
        // A resize can land on a size the card's style is not offered at.
        let sanitized = BentoLayout.sanitized(working)
        settings.update { $0.panel.bentoTiles = sanitized }
        self.working = nil
    }

    // MARK: Cards

    @ViewBuilder
    private func tileView(_ tile: BentoTile, size: CGSize) -> some View {
        switch tile.kind {
        case .settings:
            action("Settings", symbol: "gearshape.fill",
                   colors: [Color(nsColor: .systemGray), Color(nsColor: .secondaryLabelColor)],
                   size: size, perform: actions.openSettings)
                .keyboardShortcut(",", modifiers: .command)
        case .quit:
            action("Quit", symbol: "power",
                   colors: [Color(nsColor: .systemRed), Color(nsColor: .systemPink)],
                   size: size, perform: actions.quit)
                .keyboardShortcut("q", modifiers: .command)
        default:
            if tile.style == .graphic, tile.size == tile.kind.defaultSize {
                designed(tile.kind)
            } else if let module = tile.kind.module {
                flexible(tile, module: module, size: size)
            }
        }
    }

    /// The card as it was designed, at its designed size.
    @ViewBuilder
    private func designed(_ kind: BentoTileKind) -> some View {
        switch kind {
        case .cpu: cpu
        case .memory: memory
        case .gpu: gpu
        case .disk: disk
        case .battery: battery
        case .network: network
        case .thermal: thermal
        case .system: system
        case .settings, .quit: EmptyView()
        }
    }

    private var cpu: some View {
        // What is using the CPU belongs with the CPU: the five busiest processes under
        // the chip, each icon over its share.
        card(.cpu, width: Self.span(2), height: Self.span(2), header: cpuHeader) {
            VStack(spacing: Design.Space.m) {
                chip.frame(width: 140, height: 140)
                busiestRow
            }
        }
    }

    private var memory: some View {
        card(.memory, width: Self.span(2), height: Self.span(2), header: memoryHeader) {
            VStack(spacing: Design.Space.m) {
                memoryStick.frame(width: 200, height: 56)
                memoryList
            }
        }
    }

    private var gpu: some View {
        card(.gpu, width: Self.span(2), height: Self.span(2), header: gpuHeader) {
            VStack(spacing: Design.Space.m) {
                gpuDie(CGSize(width: 200, height: 106))
                gpuMeters
            }
        }
    }

    private var disk: some View {
        card(.disk, width: Self.span(2), height: Self.span(1), header: diskHeader) {
            VStack(spacing: Design.Space.s) {
                ssd.frame(width: 200, height: 44)
                diskRates
            }
        }
    }

    private var battery: some View {
        let power = engine.power.value
        // The charge, and under it how long it lasts or how long until it is full.
        return card(.battery, width: Self.span(2), height: Self.span(1), header: nil) {
            HStack(spacing: Design.Space.l) {
                if let power, !power.hasBattery {
                    batteryObject
                    bigNumber(.battery, "AC", size: 28)
                } else {
                    batteryObject.frame(width: 86, height: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        bigNumber(.battery, batteryReading, size: 30, colors: batteryColors)
                        Text(batteryState ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Design.Palette.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var network: some View {
        card(.network, width: Self.span(2), height: Self.span(1), header: networkHeader) {
            HStack(spacing: Design.Space.l) {
                networkSymbol
                networkRates()
            }
        }
    }

    private var thermal: some View {
        let thermal = engine.thermal.value
        return card(.thermal, width: Self.span(1), height: Self.span(2), header: thermalHeader) {
            VStack(spacing: Design.Space.m) {
                thermometer.frame(width: 30, height: 140)
                bigNumber(.thermal, temperatureReading ?? thermal?.pressure.label,
                          size: thermal?.cpuCelsius == nil ? 17 : 26)
            }
        }
    }

    /// The facts About This Mac gives: how long it has been up, exactly which Mac it is,
    /// and what it runs.
    private var system: some View {
        card(.system, width: Self.span(2), height: Self.span(1), header: nil) {
            systemSummary
        }
    }

    // MARK: Cards at any size

    /// A module card's parts, for drawing it at a size or in a style other than the one
    /// it was designed at.
    private struct Parts {
        /// The card's object, drawn at `native` and scaled to whatever room it gets.
        var object: AnyView
        var native: CGSize
        var reading: String?
        var readingColors: [Color]?
        /// What the reading is, where the header does not already say: "free", "uptime".
        var label: String?
        /// The readings that support it, for the larger sizes.
        var detail: AnyView?
        /// A fuller detail for a card with width to spare: names where the narrow one has
        /// only icons.
        var wideDetail: AnyView?
        /// The detail is the reading laid out its own way, so the two are not shown together.
        var detailIsReading = false
        var header: CardHeader?
        /// The header of a one-cell card, which has no room for the reading below it.
        var shortHeader: CardHeader?
        /// Over the chart, the reading the line is drawn from, where that differs: the
        /// memory chart is of what is used, the SSD's of what is read.
        var chartReading: String?
        var chartLabel: String?

        /// A long, low object, the memory stick or the SSD, which prints its reading on
        /// itself: wherever it is drawn large enough to read, the number is not repeated.
        var isFlat: Bool { native.width / native.height > 2.5 }
    }

    private func parts(_ module: PanelModule) -> Parts {
        switch module {
        case .cpu:
            let reading = engine.cpu.value.map { formatter.percent($0.total.busy) }
            return Parts(object: AnyView(chip), native: CGSize(width: 140, height: 140),
                         reading: reading, label: nil, detail: AnyView(busiestRow),
                         wideDetail: AnyView(busiestList),
                         header: cpuHeader, shortHeader: CardHeader("CPU", reading))
        case .memory:
            let free = memoryFree.map { formatter.memory($0) }
            return Parts(object: AnyView(memoryStick), native: CGSize(width: 200, height: 56),
                         reading: free, label: "free", detail: AnyView(memoryList),
                         header: memoryHeader, shortHeader: free.map { CardHeader("Free", $0) },
                         chartReading: engine.memory.value.map { formatter.percent($0.usedFraction) },
                         chartLabel: "used")
        case .gpu:
            let reading = engine.gpu.value?.primary?.utilization.map { formatter.percent($0) }
            return Parts(object: AnyView(gpuDie(CGSize(width: 200, height: 106))),
                         native: CGSize(width: 200, height: 106),
                         reading: reading, label: nil, detail: AnyView(gpuMeters),
                         header: gpuHeader, shortHeader: CardHeader("GPU", reading))
        case .disk:
            let free = engine.disk.value?.rootVolume.map { formatter.storage($0.availableBytes) }
            return Parts(object: AnyView(ssd), native: CGSize(width: 200, height: 44),
                         reading: free, label: "free", detail: AnyView(diskRates),
                         header: diskHeader, shortHeader: free.map { CardHeader("Free", $0) },
                         chartReading: engine.disk.value.map { formatter.diskRate($0.readBytesPerSecond) },
                         chartLabel: "read")
        case .battery:
            let hasBattery = engine.power.value?.hasBattery != false
            return Parts(object: AnyView(batteryObject),
                         native: hasBattery ? CGSize(width: 86, height: 40) : CGSize(width: 40, height: 40),
                         reading: hasBattery ? batteryReading : "AC", readingColors: batteryColors,
                         label: batteryState,
                         shortHeader: CardHeader("Battery", hasBattery ? batteryReading : "AC"))
        case .network:
            let network = engine.network.value ?? engine.lastKnown.network.value
            let down = network.map { formatter.networkRate($0.downloadBytesPerSecond) }
            let up = network.map { formatter.networkRate($0.uploadBytesPerSecond) }
            // Where the two rates are not drawn stacked, the upload goes with the label.
            return Parts(object: AnyView(networkSymbol), native: CGSize(width: 46, height: 36),
                         reading: down, readingColors: Self.downColors,
                         label: up.map { "download · ↑ \($0) up" } ?? "download",
                         detail: AnyView(networkRates()), detailIsReading: true,
                         header: networkHeader, shortHeader: CardHeader("Down", down))
        case .thermal:
            return Parts(object: AnyView(thermometer), native: CGSize(width: 30, height: 140),
                         reading: temperatureReading ?? engine.thermal.value?.pressure.label,
                         label: nil, header: thermalHeader,
                         shortHeader: CardHeader("CPU", temperatureReading, alert: thermalAlert))
        case .system, .processes:
            let uptime = engine.system.value.map { formatter.uptime($0.uptime) }
            return Parts(object: AnyView(Image(systemName: "laptopcomputer")
                                            .font(.system(size: 44, weight: .regular))
                                            .foregroundStyle(gradient(.system))),
                         native: CGSize(width: 64, height: 44),
                         reading: uptime, label: "uptime", detail: AnyView(systemModel),
                         shortHeader: CardHeader("Up", uptime))
        }
    }

    private func flexible(_ tile: BentoTile, module: PanelModule, size: CGSize) -> some View {
        let parts = parts(module)
        let header: CardHeader? = switch tile.style {
        // The number is in the object, so there is nothing left to say over it.
        case .inset: nil
        case .graphic, .graphicChart: tile.size == .small ? parts.shortHeader : parts.header
        case .number, .chart: parts.header
        }
        // Inside the card's padding, under its header.
        let box = CGSize(width: size.width - 16, height: size.height - (header == nil ? 23 : 42))
        return card(module, width: size.width, height: size.height, header: header) {
            switch tile.style {
            case .graphic: graphicLayout(tile.size, parts, module, box)
            case .number: numberLayout(tile.size, parts, module, tile.kind, box)
            case .chart: chartLayout(tile.size, parts, module, box)
            case .graphicChart: graphicChartLayout(tile.size, parts, module, box)
            case .inset: insetLayout(parts, box)
            }
        }
    }

    /// The object leads, the reading beside or under it as the shape allows, and the
    /// supporting readings and the history where there is room for them.
    @ViewBuilder
    private func graphicLayout(_ size: BentoTileSize, _ parts: Parts, _ module: PanelModule,
                               _ box: CGSize) -> some View {
        switch size {
        case .tall where module == .network:
            // Both directions, smaller, under the symbol.
            VStack(spacing: Design.Space.m) {
                fit(parts, in: CGSize(width: box.width, height: box.height - 56))
                networkRates(size: 15, fitting: box.width)
            }
        case .wideLarge where module == .network:
            VStack(spacing: Design.Space.m) {
                HStack(spacing: Design.Space.xl) {
                    fit(parts, in: CGSize(width: 90, height: 64))
                    networkRates()
                }
                sparkline(module, height: max(box.height - 72, 40))
            }
        case .large where module == .disk, .wideLarge where module == .disk:
            // The drive, its rates, and its history under them.
            let object = CGSize(width: min(box.width, 320), height: 64)
            VStack(spacing: Design.Space.s) {
                fit(parts, in: object)
                diskRates
                sparkline(module, height: max(box.height - fitted(parts, in: object).height - 29, 30))
            }
        case .large where module == .battery:
            // A smaller battery beside its charge, and the charge's history under them.
            VStack(spacing: Design.Space.m) {
                HStack(spacing: Design.Space.l) {
                    fit(parts, in: CGSize(width: 96, height: 46))
                    reading(parts, module, size: 30, width: box.width - 110)
                }
                sparkline(module, height: max(box.height - 66, 40))
            }
        case .extraWide where !parts.isFlat:
            // Split at the grid line between the second cell and the third, so the halves
            // line up with the cards around it: the object in one, its readings in the other.
            let half = (box.width - 16) / 2
            HStack(spacing: 16) {
                fit(parts, in: CGSize(width: half, height: box.height))
                    .frame(width: half)
                VStack(alignment: .leading, spacing: Design.Space.m) {
                    if module == .cpu {
                        // The load beside its history.
                        HStack(spacing: Design.Space.m) {
                            reading(parts, module, size: 32, width: half * 0.4)
                            sparkline(module, height: 46)
                        }
                    } else if !parts.detailIsReading {
                        reading(parts, module, size: 32, width: half)
                    }
                    parts.wideDetail ?? parts.detail
                }
                .frame(width: half, alignment: .leading)
            }
        case .small:
            fit(parts, in: box)
        case .wide where parts.isFlat:
            fit(parts, in: box)
        case .wide:
            HStack(spacing: Design.Space.l) {
                fit(parts, in: CGSize(width: box.width * 0.45, height: box.height))
                if parts.detailIsReading, let detail = parts.detail {
                    detail
                } else {
                    reading(parts, module, size: 26, width: box.width * 0.5)
                }
            }
        case .tall:
            VStack(spacing: Design.Space.m) {
                fit(parts, in: CGSize(width: box.width, height: box.height - 40))
                bigNumber(module, parts.reading, size: 24, colors: parts.readingColors, fitting: box.width)
            }
        case .large:
            VStack(spacing: Design.Space.m) {
                fit(parts, in: CGSize(width: box.width, height: box.height - 76))
                if let detail = parts.detail, parts.detailIsReading || parts.isFlat {
                    detail
                } else {
                    reading(parts, module, size: 30, alignment: .center, width: box.width)
                }
            }
        case .wideLarge where parts.isFlat, .extraWide where parts.isFlat:
            VStack(spacing: Design.Space.m) {
                fit(parts, in: CGSize(width: min(box.width, 320), height: 72))
                parts.wideDetail ?? parts.detail
            }
        case .wideLarge, .extraWide:
            HStack(spacing: Design.Space.xl) {
                fit(parts, in: CGSize(width: box.width * 0.42, height: box.height))
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    if !parts.detailIsReading { reading(parts, module, size: 32, width: box.width * 0.5) }
                    parts.wideDetail ?? parts.detail
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .tallLarge where module.historySeries == nil:
            // Nothing to chart, so the reading and the detail share the room.
            VStack(spacing: Design.Space.m) {
                fit(parts, in: CGSize(width: box.width, height: 120))
                reading(parts, module, size: 30, alignment: .center, width: box.width)
                parts.detail
            }
        case .tallLarge:
            VStack(spacing: Design.Space.m) {
                fit(parts, in: CGSize(width: box.width, height: parts.isFlat ? 72 : 120))
                if let detail = parts.detail {
                    detail
                } else {
                    reading(parts, module, size: 30, alignment: .center, width: box.width)
                }
                Spacer(minLength: 0)
                sparkline(module, height: 90)
            }
        }
    }

    /// The object with its history: over it on a one-cell card, beside it on a wide one,
    /// and on a large one with its readings beside the object and the chart under both.
    @ViewBuilder
    private func graphicChartLayout(_ size: BentoTileSize, _ parts: Parts, _ module: PanelModule,
                                    _ box: CGSize) -> some View {
        switch size {
        case .small:
            VStack(spacing: Design.Space.s) {
                fit(parts, in: CGSize(width: box.width, height: box.height * 0.45))
                sparkline(module, height: max(box.height * 0.5, 20))
            }
        case .wide:
            HStack(spacing: Design.Space.l) {
                fit(parts, in: CGSize(width: box.width * 0.4, height: box.height))
                sparkline(module, height: box.height * 0.8)
            }
        default:
            VStack(spacing: Design.Space.m) {
                HStack(spacing: Design.Space.l) {
                    fit(parts, in: CGSize(width: 64, height: 50))
                    if parts.detailIsReading, let detail = parts.detail {
                        detail
                    } else {
                        reading(parts, module, size: 26, width: box.width - 80)
                    }
                }
                sparkline(module, height: max(box.height - 66, 40))
            }
        }
    }

    /// The reading written inside the object, the way the system's battery can show it:
    /// in the label colour with a halo of the card's, so it reads over the charge and over
    /// the empty part alike.
    private func insetLayout(_ parts: Parts, _ box: CGSize) -> some View {
        let power = engine.power.value
        let object = ZStack {
            BatteryGraphic(fraction: (power?.percentage ?? 0) / 100, isCharging: false,
                           charge: batteryIsLow ? Color(nsColor: .systemRed) : palette(.battery)[0])
            HStack(spacing: 1) {
                if power?.isCharging == true {
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .heavy))
                }
                Text(parts.reading ?? MetricFormatter.unavailable)
                    .font(.system(size: 17, weight: .heavy).monospacedDigit())
            }
            .foregroundStyle(Design.Palette.primaryText)
            .shadow(color: BentoCard<EmptyView>.surface, radius: 1)
            .shadow(color: BentoCard<EmptyView>.surface, radius: 1)
            // Centred on the body, not on the body and its terminal.
            .offset(x: -3)
        }
        return fit(AnyView(object), native: parts.native, in: box)
    }

    /// The reading leads, as large as the card allows, over what it is.
    @ViewBuilder
    private func numberLayout(_ size: BentoTileSize, _ parts: Parts, _ module: PanelModule,
                              _ kind: BentoTileKind, _ box: CGSize) -> some View {
        let symbol = Image(systemName: kind == .network ? "wifi" : kind.symbolName)
            .foregroundStyle(gradient(parts.readingColors ?? palette(module)))
        // The detail beside or under the number, unless it is the number over again.
        let detail = parts.detailIsReading ? nil : parts.detail
        switch size {
        case .small:
            reading(parts, module, size: 26, alignment: .center, width: box.width)
        case .wide:
            HStack(spacing: Design.Space.l) {
                symbol.font(.system(size: 28, weight: .semibold))
                reading(parts, module, size: 36, width: box.width - 52)
            }
        case .tall:
            VStack(spacing: Design.Space.m) {
                symbol.font(.system(size: 30, weight: .semibold))
                reading(parts, module, size: 30, alignment: .center, width: box.width)
            }
        case .large:
            VStack(spacing: Design.Space.s) {
                symbol.font(.system(size: 26, weight: .semibold))
                reading(parts, module, size: 50, alignment: .center, width: box.width)
            }
        case .wideLarge, .extraWide:
            if let detail = parts.wideDetail ?? detail {
                HStack(spacing: Design.Space.xl) {
                    VStack(alignment: .leading, spacing: Design.Space.s) {
                        symbol.font(.system(size: 26, weight: .semibold))
                        reading(parts, module, size: 52, width: box.width * 0.45)
                    }
                    detail.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: Design.Space.s) {
                    symbol.font(.system(size: 30, weight: .semibold))
                    reading(parts, module, size: 60, alignment: .center, width: box.width)
                }
            }
        case .tallLarge:
            VStack(spacing: Design.Space.l) {
                symbol.font(.system(size: 28, weight: .semibold))
                reading(parts, module, size: 50, alignment: .center, width: box.width)
                detail
            }
        }
    }

    /// The reading over its history, the line filling what the card has left.
    private func chartLayout(_ size: BentoTileSize, _ parts: Parts, _ module: PanelModule,
                             _ box: CGSize) -> some View {
        // A narrow card has room for the number alone.
        let isNarrow = size.columns == 1
        let number: CGFloat = size == .small ? 18 : size == .wide || size == .tall ? 22 : 28
        let network = engine.network.value ?? engine.lastKnown.network.value
        return VStack(alignment: .leading, spacing: Design.Space.xs) {
            if module == .network, !isNarrow {
                // Both directions over the chart.
                HStack(spacing: Design.Space.l) {
                    rate("arrow.down", network.map { formatter.networkRate($0.downloadBytesPerSecond) },
                         colors: Self.downColors, size: number * 0.8)
                    rate("arrow.up", network.map { formatter.networkRate($0.uploadBytesPerSecond) },
                         colors: Self.upColors, size: number * 0.8)
                    Spacer(minLength: 0)
                }
            } else {
            HStack(alignment: .firstTextBaseline, spacing: Design.Space.xs) {
                bigNumber(module, parts.chartReading ?? parts.reading, size: number,
                          colors: parts.readingColors, fitting: isNarrow ? box.width : box.width * 0.55)
                if !isNarrow, let label = parts.chartLabel ?? parts.label {
                    Text(label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Design.Palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            }
            sparkline(module, height: max(box.height - number - 10, 24), tint: parts.readingColors?.first)
        }
    }

    /// The object at its own proportions, as large as `box` allows.
    private func fit(_ parts: Parts, in box: CGSize) -> some View {
        fit(parts.object, native: parts.native, in: box)
    }

    private func fit(_ object: AnyView, native: CGSize, in box: CGSize) -> some View {
        let size = Self.fitted(native, in: box)
        let scale = size.width / native.width
        return object
            .frame(width: native.width, height: native.height)
            .scaleEffect(scale)
            .frame(width: size.width, height: size.height)
    }

    /// The size the object is drawn at in `box`.
    private func fitted(_ parts: Parts, in box: CGSize) -> CGSize {
        Self.fitted(parts.native, in: box)
    }

    private static func fitted(_ native: CGSize, in box: CGSize) -> CGSize {
        let scale = max(0.1, min(box.width / native.width, box.height / native.height, 2.5))
        return CGSize(width: native.width * scale, height: native.height * scale)
    }

    private func reading(_ parts: Parts, _ module: PanelModule, size: CGFloat,
                         alignment: HorizontalAlignment = .leading, width: CGFloat? = nil) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            bigNumber(module, parts.reading, size: size, colors: parts.readingColors, fitting: width)
            if let label = parts.label {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// The module's recent history, in the colour of the reading over it. The network's
    /// line is its download, so it takes the download's blue wherever it is drawn.
    @ViewBuilder
    private func sparkline(_ module: PanelModule, height: CGFloat, tint: Color? = nil) -> some View {
        if let series = module.historySeries {
            let colour = tint ?? (module == .network ? Self.downColors[0] : palette(module)[0])
            Sparkline(ChartSeries(series.key, from: engine.history, tint: colour,
                                  domain: series.domain),
                      settings: settings.settings.charts, height: height)
        }
    }

    // MARK: Objects and readings

    private var chip: some View {
        let cpu = engine.cpu.value
        // Each core's own load beside its kind. A core the system did not classify is
        // drawn as a performance core: that is what a chip without the split has.
        let cores = cpu.map { cpu in
            cpu.perCore.indices.map { index in
                (kind: index < cpu.coreKinds.count ? cpu.coreKinds[index] : .unknown,
                 busy: cpu.perCore[index].busy)
            }
        } ?? []
        return ChipGraphic(name: engine.system.value?.chipName,
                           performance: cores.filter { $0.kind != .efficiency }.map(\.busy),
                           efficiency: cores.filter { $0.kind == .efficiency }.map(\.busy),
                           performanceColors: palette(.cpu, onCard: false),
                           efficiencyColors: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)])
    }

    private var cpuHeader: CardHeader {
        let system = engine.system.value
        let cores = system.map(\.physicalCores).flatMap { $0 > 0 ? $0 : nil }
            ?? engine.cpu.value.map(\.perCore.count)
        return CardHeader("CPU", cores.map { "\($0) cores" })
    }

    /// The five busiest processes, each icon over its share.
    @ViewBuilder
    private var busiestRow: some View {
        let processes = processList
        let busiest = processes.map {
            Array($0.list.processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        } ?? []
        if busiest.isEmpty {
            // Nothing yet, not even from last time: the row's shape, so the chip does not
            // move when the processes arrive.
            HStack(spacing: Design.Space.l) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(spacing: 2) {
                        Circle().fill(Design.Palette.track).frame(width: 16, height: 16)
                        Capsule().fill(Design.Palette.track).frame(width: 18, height: 6)
                            .frame(height: 11)
                    }
                }
            }
            .accessibilityHidden(true)
        } else {
            HStack(spacing: Design.Space.l) {
                ForEach(busiest, id: \.pid) { process in
                    VStack(spacing: 2) {
                        ProcessIcon(process: process, size: 16)
                        Text(formatter.unclampedPercent(process.cpuPercent, decimals: 0))
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Design.Palette.secondaryText)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .lastKnown(processes?.isLastKnown == true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Busiest processes: " + busiest.map(\.name).joined(separator: ", "))
        }
    }

    /// Free is what the fill leaves: everything not counted as used, the way the SSD
    /// reports its available space.
    private var memoryFree: UInt64? {
        engine.memory.value.map { $0.totalBytes > $0.usedBytes ? $0.totalBytes - $0.usedBytes : 0 }
    }

    private var memoryHeader: CardHeader {
        CardHeader("Memory", engine.memory.value.map { Self.marketingCapacity($0.totalBytes) })
    }

    private var memoryStick: some View {
        let memory = engine.memory.value
        let used = memory.map { $0.totalBytes > 0 ? Double($0.usedBytes) / Double($0.totalBytes) : 0 }
        return MemoryGraphic(label: memoryFree.map { "\(formatter.memory($0)) free" },
                             fraction: used ?? 0, load: palette(.memory, onCard: false)[0])
    }

    /// The biggest users, ranked by what they hold rather than by how busy they are: the
    /// process sample keeps the largest idle ones for exactly this.
    private var memoryList: some View {
        let processes = processList
        let top = processes.map {
            Array($0.list.processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5))
        } ?? []
        return processRows(top.map { ($0, formatter.memory($0.memoryBytes)) },
                           isLastKnown: processes?.isLastKnown == true)
    }

    /// The busiest processes by name and share, for a card with the width for names.
    private var busiestList: some View {
        let processes = processList
        let busiest = processes.map {
            Array($0.list.processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        } ?? []
        return processRows(busiest.map { ($0, formatter.unclampedPercent($0.cpuPercent, decimals: 0)) },
                           isLastKnown: processes?.isLastKnown == true)
    }

    /// Up to five processes, each icon, name and figure on a row, or the rows' shape
    /// before there is a list to show.
    @ViewBuilder
    private func processRows(_ rows: [(ProcessRow, String)], isLastKnown: Bool) -> some View {
        if rows.isEmpty {
            VStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    HStack(spacing: Design.Space.xs) {
                        Circle().fill(Design.Palette.track).frame(width: 13, height: 13)
                        Capsule().fill(Design.Palette.track).frame(width: 90, height: 7)
                        Spacer(minLength: Design.Space.s)
                        Capsule().fill(Design.Palette.track).frame(width: 34, height: 7)
                    }
                    .frame(height: 15)
                }
            }
            .padding(.horizontal, Design.Space.xs)
            .accessibilityHidden(true)
        } else {
            VStack(spacing: 2) {
                ForEach(rows, id: \.0.pid) { process, value in
                    HStack(spacing: Design.Space.xs) {
                        ProcessIcon(process: process, size: 13)
                        Text(process.name)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Design.Palette.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: Design.Space.s)
                        Text(value)
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Design.Palette.secondaryText)
                    }
                    .frame(height: 15)
                }
            }
            .padding(.horizontal, Design.Space.xs)
            .lastKnown(isLastKnown)
        }
    }

    /// The load is left to the die, whose cores light up with it.
    private var gpuHeader: CardHeader {
        let cores = engine.gpu.value?.primary?.coreCount ?? engine.system.value?.gpuCoreCount
        return CardHeader("GPU", cores.map { "\($0) cores" })
    }

    @ViewBuilder
    private func gpuDie(_ size: CGSize) -> some View {
        let device = engine.gpu.value?.primary
        if let cores = device?.coreCount ?? engine.system.value?.gpuCoreCount, cores > 0 {
            GPUDie(cores: cores, load: device?.utilization ?? 0, colors: palette(.gpu, onCard: false),
                   size: size)
        } else {
            bigNumber(.gpu, nil, size: 24)
        }
    }

    /// The die already draws the overall load, so the meters carry what it cannot: the
    /// GPU's memory, then the renderer and tiler the driver reports. macOS reports the
    /// GPU only as a whole, never core by core.
    private var gpuMeters: some View {
        let device = engine.gpu.value?.primary
        // What the GPU holds of the shared memory, against the most macOS will let it
        // have: not memory of its own, a share of the one pool the Memory card shows.
        var memory: GPUChannel?
        if let used = device?.vramUsedBytes, let total = device?.vramTotalBytes, total > 0 {
            memory = GPUChannel(name: "Memory", value: Double(used) / Double(total),
                                detail: "\(formatter.memory(used)) of \(formatter.memory(total))")
        }
        return GPUMeters(channels: [memory,
                                    device?.rendererUtilization.map { GPUChannel(name: "Renderer", value: $0) },
                                    device?.tilerUtilization.map { GPUChannel(name: "Tiler", value: $0) }]
                             .compactMap { $0 },
                         colors: palette(.gpu), formatter: formatter)
            .padding(.horizontal, Design.Space.xs)
    }

    private var diskHeader: CardHeader {
        CardHeader("SSD", engine.disk.value?.rootVolume.map { formatter.storage($0.totalBytes) })
    }

    /// How full the disk is, from the same available space as the label printed on it so
    /// the two agree, the way Finder and System Settings count it.
    private var ssd: some View {
        let root = engine.disk.value?.rootVolume
        return SSDGraphic(fraction: root.map { $0.totalBytes > 0
                              ? 1 - Double($0.availableBytes) / Double($0.totalBytes) : 0 } ?? 0,
                          colors: palette(.disk, onCard: false),
                          label: root.map { "\(formatter.storage($0.availableBytes)) free" })
    }

    private var diskRates: some View {
        HStack(spacing: Design.Space.xl) {
            diskRate("Read", engine.disk.value?.readBytesPerSecond)
            diskRate("Write", engine.disk.value?.writeBytesPerSecond)
        }
    }

    private var batteryReading: String? {
        engine.power.value?.percentage.map { formatter.percentValue($0) }
    }

    /// Red at 20% and under while not charging, the way the system's own battery goes.
    private var batteryIsLow: Bool {
        guard let power = engine.power.value else { return false }
        return (power.percentage ?? 0) / 100 <= 0.2 && !power.isCharging
    }

    private var batteryColors: [Color]? {
        batteryIsLow ? [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)] : nil
    }

    @ViewBuilder
    private var batteryObject: some View {
        let power = engine.power.value
        if let power, !power.hasBattery {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(gradient(.battery))
        } else {
            BatteryGraphic(fraction: (power?.percentage ?? 0) / 100, isCharging: power?.isCharging ?? false,
                           charge: batteryIsLow ? Color(nsColor: .systemRed) : palette(.battery)[0])
        }
    }

    private static let upColors = [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)]
    private static let downColors = [Color(nsColor: .systemBlue), Color(nsColor: .systemCyan)]

    /// The network's name where macOS gives it. Not "Wi-Fi": the symbol says that.
    private var networkHeader: CardHeader? {
        (engine.network.value ?? engine.lastKnown.network.value)?.wifi?.ssid.map { CardHeader($0) }
    }

    /// Wi-Fi when that is the connection, the generic network glyph otherwise.
    private var networkSymbol: some View {
        let network = engine.network.value ?? engine.lastKnown.network.value
        return Image(systemName: network?.wifi != nil || network == nil ? "wifi" : "network")
            .font(.system(size: 36, weight: .semibold))
            .foregroundStyle(gradient(.network))
    }

    /// Upload over download, in Activity Monitor's colours for the two directions: red
    /// going out, blue coming in. The last rates, greyed, while the live ones return.
    private func networkRates(size: CGFloat = 21, fitting width: CGFloat? = nil) -> some View {
        let isLastKnown = engine.network.value == nil && engine.lastKnown.network.value != nil
        let network = engine.network.value ?? engine.lastKnown.network.value
        return VStack(alignment: .leading, spacing: 0) {
            rate("arrow.up", network.map { formatter.networkRate($0.uploadBytesPerSecond) },
                 colors: Self.upColors, size: size, fitting: width)
            rate("arrow.down", network.map { formatter.networkRate($0.downloadBytesPerSecond) },
                 colors: Self.downColors, size: size, fitting: width)
        }
        .lastKnown(isLastKnown)
    }

    private var temperatureReading: String? {
        engine.thermal.value?.cpuCelsius.map { formatter.temperature($0) }
    }

    /// The CPU's, and the thermal state only once it is past nominal: the state is worth
    /// a word when the Mac is holding itself back, not while all is well.
    private var thermalHeader: CardHeader {
        CardHeader(engine.thermal.value?.cpuCelsius == nil ? "Thermal state" : "CPU", alert: thermalAlert)
    }

    private var thermalAlert: String? {
        engine.thermal.value.flatMap { $0.pressure > .nominal ? $0.pressure.label : nil }
    }

    /// Red whatever the metric's colour: on a thermometer red is the reading, and the top
    /// of the scale is where it means danger.
    private var thermometer: some View {
        ThermometerGraphic(fraction: engine.thermal.value?.cpuCelsius.map { min(max(($0 - 30) / 70, 0), 1) } ?? 0,
                           colors: [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)])
    }


    private var systemSummary: some View {
        let system = engine.system.value
        return HStack(spacing: Design.Space.l) {
            VStack(spacing: 0) {
                bigNumber(.system, system.map { formatter.uptime($0.uptime) }, size: 26)
                Text("uptime")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
            }
            if system != nil {
                Rectangle()
                    .fill(Design.Palette.separator)
                    .frame(width: 1, height: 44)
                systemModel
            }
        }
    }

    /// Exactly which Mac this is, and what it runs.
    @ViewBuilder
    private var systemModel: some View {
        if let system = engine.system.value {
            let model = Self.model(system)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Palette.primaryText)
                Text(model.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
                Text("\(system.osName) \(system.osVersion)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Design.Palette.tertiaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    // MARK: Pieces

    /// The process list now, or the last one while the list re-establishes its baseline
    /// on opening, which the cards grey rather than leave empty.
    private var processList: (list: ProcessSnapshot, isLastKnown: Bool)? {
        if let current = engine.processes.value { return (current, false) }
        return engine.lastKnown.processes.value.map { ($0, true) }
    }

    /// One of the panel's two actions as a card of its own: a symbol in its gradient, the
    /// whole card the button.
    private func action(_ title: String, symbol: String, colors: [Color], size: CGSize,
                        perform: @escaping @MainActor () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        // The symbol alone: a gear and a power sign need no words under them.
        return Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(gradient(colors))
                .frame(width: size.width, height: size.height)
        }
        .buttonStyle(BentoActionStyle())
        .background(shape.fill(BentoCard<EmptyView>.surface))
        .clipShape(shape)
        .accessibilityLabel(title)
    }

    private func card<Content: View>(_ module: PanelModule, width: CGFloat, height: CGFloat,
                                     header: CardHeader?,
                                     @ViewBuilder content: () -> Content) -> some View {
        BentoCard(module: module, header: header, ring: palette(module)[0],
                  isActive: layout?.detailModule == module, layout: layout,
                  size: CGSize(width: width, height: height), content: content())
    }

    /// The card's reading, large and bold in the card's gradient. A spinner while the
    /// module waits for its first reading, a dash where there is none to give.
    ///
    /// With `fitting`, the size comes down until the text fits that width, worked out from
    /// its length: a number that cannot shrink to fit is cut short, and "7.7 G…" is worse
    /// than a smaller "7.7 GB".
    @ViewBuilder
    private func bigNumber(_ module: PanelModule, _ text: String?, size: CGFloat,
                           colors: [Color]? = nil, fitting width: CGFloat? = nil) -> some View {
        if text == nil, engine.isCollecting(module) {
            ProgressView().controlSize(.small).frame(height: size)
        } else {
            let characters = CGFloat(max((text ?? MetricFormatter.unavailable).count, 1))
            let fitted = width.map { min(size, $0 / (characters * 0.62)) } ?? size
            Text(text ?? MetricFormatter.unavailable)
                .font(.system(size: fitted, weight: .bold).monospacedDigit())
                .foregroundStyle(text == nil ? AnyShapeStyle(Design.Palette.tertiaryText)
                                             : AnyShapeStyle(gradient(colors ?? palette(module))))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
    }

    private func diskRate(_ label: String, _ bytesPerSecond: Double?) -> some View {
        HStack(spacing: Design.Space.xs) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Design.Palette.secondaryText)
            Text(bytesPerSecond.map { formatter.diskRate($0) } ?? MetricFormatter.unavailable)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Design.Palette.primaryText)
                .contentTransition(.numericText())
        }
    }

    private func rate(_ symbol: String, _ value: String?, colors: [Color],
                      size: CGFloat = 21, fitting width: CGFloat? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.xs) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.72, weight: .bold))
                .foregroundStyle(gradient(colors))
                .frame(width: size * 0.76)
            bigNumber(.network, value, size: size, colors: colors,
                      fitting: width.map { $0 - size * 0.76 - Design.Space.xs })
        }
    }

    private var batteryState: String? {
        engine.power.value.map(batteryCaption)
    }

    private func batteryCaption(_ power: PowerSnapshot) -> String {
        guard power.hasBattery else { return "Power adapter" }
        if power.isCharging {
            return power.timeToFull.map { "Full in \(formatter.duration($0))" } ?? "Charging"
        }
        if power.isFullyCharged { return "Fully charged" }
        return power.timeToEmpty.map { "\(formatter.duration($0)) left" } ?? "On battery"
    }

    private func gradient(_ module: PanelModule) -> LinearGradient {
        gradient(palette(module))
    }

    private func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Two colours per card, drawn as a gradient the way Apple sets its headline words,
    /// and chosen so the nine cards read as nine different things at a glance. A colour
    /// the user has set for the metric in Appearance wins over these.
    ///
    /// `onCard` is for colour drawn straight on the card rather than on one of the dark
    /// objects (the chip, the memory module, the GPU die, the SSD). There, a colour the
    /// user picked that is too pale to read on a white card gives way to the label
    /// colour in light appearance: white is a fine choice for the dark panel and an
    /// invisible number on a light one.
    private func palette(_ module: PanelModule, onCard: Bool = true) -> [Color] {
        Self.palette(module, theme: settings.settings.theme, onCard: onCard)
    }

    static func palette(_ module: PanelModule, theme: ThemeSettings, onCard: Bool = true) -> [Color] {
        if let custom = theme.color(for: module.requiredSource) {
            let color = onCard ? Self.legibleOnCard(custom) : Color(themeColor: custom)
            return [color, color]
        }
        let pair: (NSColor, NSColor)
        switch module {
        case .cpu: pair = (.systemBlue, .systemCyan)
        case .memory: pair = (.systemIndigo, .systemBlue)
        case .gpu: pair = (.systemPurple, .systemPink)
        case .network: pair = (.systemOrange, .systemYellow)
        case .disk: pair = (.systemTeal, .systemMint)
        case .battery: pair = (.systemGreen, .systemMint)
        case .thermal: pair = (.systemRed, .systemOrange)
        case .processes: pair = (.systemPink, .systemRed)
        case .system: pair = (.systemGray, .secondaryLabelColor)
        }
        return [Color(nsColor: pair.0), Color(nsColor: pair.1)]
    }

    private static func legibleOnCard(_ theme: ThemeColor) -> Color {
        let color = NSColor(srgbRed: theme.red, green: theme.green, blue: theme.blue, alpha: 1)
        let luminance = 0.2126 * theme.red + 0.7152 * theme.green + 0.0722 * theme.blue
        return Color(nsColor: NSColor(name: nil) { appearance in
            !appearance.isDark && luminance > 0.75 ? .labelColor : color
        })
    }

    /// The cards' own surface, for anything drawn to match them.
    static var surface: Color { BentoCard<EmptyView>.surface }

    /// Exactly which Mac: "MacBook Pro (16-inch, 2021)" and "MacBookPro18,2" become
    /// "MacBook Pro 16-inch" over "2021 · MacBookPro18,2".
    static func model(_ system: SystemInfoSnapshot) -> (name: String, detail: String) {
        let family = system.modelName.components(separatedBy: " (").first ?? system.modelName
        var parts: [String] = []
        if let open = system.modelName.firstIndex(of: "("), let close = system.modelName.lastIndex(of: ")"),
           open < close {
            parts = system.modelName[system.modelName.index(after: open)..<close]
                .components(separatedBy: ", ")
        }
        let size = parts.first { $0.contains("inch") }
        let rest = parts.filter { $0 != size } + [system.modelIdentifier].filter { !$0.isEmpty }
        return (size.map { "\(family) \($0)" } ?? family, rest.joined(separator: " · "))
    }

    /// Installed memory the way it is sold: 34,359,738,368 bytes is "32 GB", not the
    /// "34.4 GB" a decimal formatter makes of it.
    private static func marketingCapacity(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / Double(1 << 30)
        return "\(Int(gigabytes.rounded())) GB"
    }
}

// MARK: - Card

extension View {
    /// Greys a reading that is the last one seen rather than a live one, and brings it
    /// back to colour when the live one replaces it.
    func lastKnown(_ isLastKnown: Bool) -> some View {
        grayscale(isLastKnown ? 1 : 0)
            .opacity(isLastKnown ? 0.45 : 1)
            .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: isLastKnown)
    }
}

/// One card: its content centred, a caption under it. Reports the pointer the way a list
/// row does, so the detail opens beside the panel level with the card, and takes a ring
/// in its own colour while that detail is open.
private struct BentoCard<Content: View>: View {
    let module: PanelModule
    /// Nil for a card whose content says it all.
    let header: CardHeader?
    let ring: Color
    /// Its detail is open beside the panel.
    let isActive: Bool
    let layout: PanelLayoutState?
    let size: CGSize
    let content: Content

    @State private var frame: CGRect = .zero

    /// White on Apple's light grey, or a dark grey a step up from the black panel.
    static var surface: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(white: 0.11, alpha: 1) : .white })
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: Design.Space.s) {
            if let header {
                header.view
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Design.Space.m)
        .padding(.top, header == nil ? Design.Space.l : Design.Space.m + 2)
        .padding(.bottom, Design.Space.m + 3)
        .frame(width: size.width, height: size.height)
        .background(shape.fill(Self.surface))
        .overlay {
            if isActive { shape.strokeBorder(ring, lineWidth: 2) }
        }
        .contentShape(shape)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onContinuousHover { phase in
            // While the cards are being arranged, the detail would only be in the way.
            guard layout?.isEditing != true else { return }
            switch phase {
            case .active: layout?.rowHover?(module, frame)
            case .ended: layout?.rowHover?(module, nil)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// What a card says about itself, over it: "Memory: 32 GB". The fact that matters
/// rather than the card's name, so a card whose object says it all has none.
struct CardHeader: Equatable {
    var label: String
    var value: String?
    /// A word that needs attention after it, in red: a thermal state past nominal.
    var alert: String?

    init(_ label: String, _ value: String? = nil, alert: String? = nil) {
        self.label = label
        self.value = value
        self.alert = alert
    }

    var view: some View {
        HStack(spacing: 3) {
            Text(value == nil ? label : label + ":")
                .font(.system(size: 12, weight: value == nil ? .bold : .semibold))
                .foregroundStyle(value == nil ? Design.Palette.primaryText : Design.Palette.secondaryText)
            if let value {
                Text(value)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(Design.Palette.primaryText)
            }
            if let alert {
                Text("· " + alert)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(nsColor: .systemRed))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// An action card as a button: nothing of its own at rest, a step darker under the
/// pointer and another while pressed, the way a system button answers. The card behind
/// it supplies the surface and the rounded corners.
private struct BentoActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BentoActionBody(configuration: configuration)
    }
}

private struct BentoActionBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background(Design.Palette.primaryText
                .opacity(configuration.isPressed ? 0.12 : isHovering ? 0.06 : 0))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(Design.Motion.respectingAccessibility(Design.Motion.hover), value: isHovering)
    }
}

// MARK: - Graphics

/// An Apple silicon package drawn the way Apple shows it: a square, sharp-cornered die
/// in near-black with a faint sheen and a bright bevel, the logo and chip in brushed
/// silver, and the tier — PRO, MAX, ULTRA — in its own gradient underneath.
///
/// Under the name, the CPU cores as blocks on the die, each filling from the bottom with
/// its own load: the performance cores as larger squares in the card's blue, two rows of
/// them, and the efficiency cores as narrower blocks in green beside them, so the two
/// kinds read apart by shape and by colour. The chip is drawn dark in both appearances:
/// it is an object, and Apple's chip is black on a white page too.
private struct ChipGraphic: View {
    /// "Apple M1 Max", or whatever the system reports for a chip that is not Apple's.
    let name: String?
    /// Each performance core's busy fraction, then each efficiency core's.
    let performance: [Double]
    let efficiency: [Double]
    let performanceColors: [Color]
    let efficiencyColors: [Color]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ChipFace()
                if performance.isEmpty && efficiency.isEmpty {
                    // No cores read yet: the name alone, at the size it has on its own.
                    lettering(side: side, scale: 1)
                } else {
                    // The name in the top half, the cores filling the bottom half to within
                    // 4pt of the die's edges.
                    VStack(spacing: 0) {
                        lettering(side: side, scale: 0.62)
                            .frame(height: side / 2)
                        ChipCores(performance: performance, efficiency: efficiency,
                                  size: CGSize(width: side - ChipCores.gap * 2,
                                               height: side / 2 - ChipCores.gap),
                                  performanceColors: performanceColors,
                                  efficiencyColors: efficiencyColors)
                            .padding(.horizontal, ChipCores.gap)
                            .padding(.bottom, ChipCores.gap)
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The brushed silver the chips' lettering is set in, the CPU's and the GPU's.
    static let silver = LinearGradient(colors: [Color(white: 0.97), Color(white: 0.66)],
                                       startPoint: .top, endPoint: .bottom)

    @ViewBuilder
    private func lettering(side: CGFloat, scale: CGFloat) -> some View {
        let size = side * scale
        if let name, name.hasPrefix("Apple ") {
            // "Apple M1 Max" is set as the chip is marked: the logo and "M1" in silver,
            // and the tier under it in that tier's colours.
            let words = name.dropFirst("Apple ".count).split(separator: " ", maxSplits: 1)
            VStack(spacing: size * 0.02) {
                HStack(alignment: .center, spacing: size * 0.01) {
                    Image(systemName: "applelogo")
                        .font(.system(size: size * 0.25, weight: .regular))
                    Text(words.first.map(String.init) ?? "")
                        .font(.system(size: size * 0.3, weight: .semibold))
                        .tracking(-size * 0.005)
                }
                .foregroundStyle(Self.silver)
                if words.count > 1 {
                    Text(words[1].uppercased())
                        .font(.system(size: size * 0.14, weight: .semibold))
                        .tracking(size * 0.01)
                        .foregroundStyle(LinearGradient(colors: Self.tierColors(String(words[1])),
                                                        startPoint: .leading, endPoint: .trailing))
                }
            }
            .offset(x: -size * 0.01)
        } else if let name {
            Text(name)
                .font(.system(size: size * 0.1, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Self.silver)
                .padding(size * 0.08)
        }
    }

    /// Apple's colours for each tier's name: PRO in cyan to blue, MAX in lavender to
    /// pink, ULTRA in blue to violet. Anything newer falls back to silver.
    private static func tierColors(_ tier: String) -> [Color] {
        switch tier.lowercased() {
        case "pro": return [Color(red: 0.42, green: 0.86, blue: 1.0), Color(red: 0.3, green: 0.55, blue: 1.0)]
        case "max": return [Color(red: 0.7, green: 0.58, blue: 1.0), Color(red: 0.93, green: 0.45, blue: 0.86)]
        case "ultra": return [Color(red: 0.45, green: 0.62, blue: 1.0), Color(red: 0.62, green: 0.42, blue: 1.0)]
        default: return [Color(white: 0.97), Color(white: 0.66)]
        }
    }
}

/// The CPU cores laid out on the die: performance cores as squares in two rows, the
/// efficiency cores beside them as blocks a little over half as wide, each rising from
/// the bottom with its own load.
private struct ChipCores: View {
    let performance: [Double]
    let efficiency: [Double]
    /// The area the cores fill, edge to edge.
    let size: CGSize
    let performanceColors: [Color]
    let efficiencyColors: [Color]

    /// Between cores, between the two kinds, and from the die's edges.
    static let gap: CGFloat = 4
    private static let efficiencyWidth: CGFloat = 0.55

    var body: some View {
        let pColumns = Self.columns(performance.count)
        let eColumns = Self.columns(efficiency.count)
        let units = CGFloat(pColumns) + CGFloat(eColumns) * Self.efficiencyWidth
        let gaps = CGFloat(max(pColumns + eColumns - 1, 0)) * Self.gap
        let width = (size.width - gaps) / max(units, 1)
        let height = (size.height - Self.gap) / 2
        HStack(alignment: .top, spacing: Self.gap) {
            if pColumns > 0 {
                cluster(performance, columns: pColumns,
                        size: CGSize(width: width, height: height), colors: performanceColors)
            }
            if eColumns > 0 {
                cluster(efficiency, columns: eColumns,
                        size: CGSize(width: width * Self.efficiencyWidth, height: height),
                        colors: efficiencyColors)
            }
        }
    }

    /// Two rows, filled left to right along the top row first.
    private static func columns(_ count: Int) -> Int {
        Int((Double(count) / 2).rounded(.up))
    }

    private func cluster(_ loads: [Double], columns: Int, size: CGSize,
                         colors: [Color]) -> some View {
        VStack(spacing: Self.gap) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < loads.count {
                            CoreBlock(fraction: loads[index], colors: colors)
                                .frame(width: size.width, height: size.height)
                        } else {
                            Color.clear.frame(width: size.width, height: size.height)
                        }
                    }
                }
            }
        }
    }
}

/// One core: a dark block with a hairline edge, filled from the bottom to its load.
/// Nearly square-cornered, as die diagrams draw their blocks.
private struct CoreBlock: View {
    let fraction: Double
    let colors: [Color]

    var body: some View {
        let block = RoundedRectangle(cornerRadius: 1, style: .continuous)
        ZStack {
            block.fill(Color.white.opacity(0.07))
            FillFromBottom(fraction: fraction)
                .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                .clipShape(block)
            block.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

/// The GPU's load as the driver reports it, each figure by its full name with its
/// percentage, over a segmented meter: a row of thin vertical ticks that light from the
/// left, the way a hardware level meter reads.
/// One meter on the GPU card: a 0...1 level, shown as a percentage unless it has a
/// reading of its own to show instead.
private struct GPUChannel {
    let name: String
    let value: Double
    var detail: String?
}

private struct GPUMeters: View {
    let channels: [GPUChannel]
    let colors: [Color]
    let formatter: MetricFormatter

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(channels.enumerated()), id: \.offset) { _, channel in
                VStack(spacing: 3) {
                    HStack {
                        Text(channel.name)
                        Spacer(minLength: Design.Space.xs)
                        Text(channel.detail ?? formatter.percent(channel.value)).monospacedDigit()
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
                    TickMeter(fraction: channel.value, colors: colors)
                        .frame(height: 7)
                }
            }
        }
    }
}

/// A level drawn as a row of thin vertical ticks: the lit ones in the gradient, the rest
/// a pale wash of it.
private struct TickMeter: View {
    let fraction: Double
    let colors: [Color]

    var body: some View {
        let fraction = min(max(fraction, 0), 1)
        ZStack {
            Ticks(fraction: fraction, drawsLit: false).fill(colors[0].opacity(0.18))
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .mask(Ticks(fraction: fraction, drawsLit: true))
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

/// Thin vertical ticks across the rect, a fixed width and pitch, so a wider meter has
/// more of them rather than fatter ones: those up to `fraction` of the way across, or
/// the rest.
private struct Ticks: Shape {
    let fraction: Double
    let drawsLit: Bool

    private static let width: CGFloat = 2
    private static let gap: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(Int((rect.width + Self.gap) / (Self.width + Self.gap)), 1)
        let lit = Int((fraction * Double(count)).rounded())
        for index in drawsLit ? 0..<lit : lit..<count {
            let x = rect.minX + CGFloat(index) * (Self.width + Self.gap)
            path.addRoundedRect(in: CGRect(x: x, y: rect.minY, width: Self.width, height: rect.height),
                                cornerSize: CGSize(width: 0.5, height: 0.5))
        }
        return path
    }
}

/// The GPU as a packaged chip: the CPU chip's face, gold legs standing off all four
/// edges, and its cores laid out as on the die, in four clusters with a wider channel
/// between them, so a 32-core GPU reads as four blocks of eight. The chip's name,
/// "GPU" in the CPU chip's silver, is set across the middle over the cores, so the
/// clusters close up around it and the cores get the whole face.
///
/// Blocks switch on one by one as the load rises, in reading order across the whole
/// grid: at 18% of 32 cores, the first six. macOS reports the GPU only as a whole, so
/// the blocks are lit in order, which reads as a level, rather than scattered, which
/// would claim to know which cores are busy.
private struct GPUDie: View {
    let cores: Int
    let load: Double
    let colors: [Color]
    /// The whole chip, legs included; the blocks follow from it.
    let size: CGSize

    /// How far the legs stand off the package.
    private static let leg: CGFloat = 4
    /// From the package's edge to the blocks.
    private static let inset: CGFloat = 5
    private static let gap: CGFloat = 2
    /// Between the clusters.
    private static let channel: CGFloat = 4

    var body: some View {
        let columns = cores % 8 == 0 || cores > 8 ? min(cores, 8) : cores
        let rows = Int((Double(cores) / Double(columns)).rounded(.up))
        // Split down the middle each way where the grid divides evenly.
        let columnSplit = columns >= 4 && columns % 2 == 0 ? columns / 2 : nil
        let rowSplit = rows >= 2 && rows % 2 == 0 ? rows / 2 : nil
        let package = CGSize(width: size.width - Self.leg * 2, height: size.height - Self.leg * 2)
        let across = Self.gap * CGFloat(columns - 1) + (columnSplit == nil ? 0 : Self.channel - Self.gap)
        let down = Self.gap * CGFloat(rows - 1) + (rowSplit == nil ? 0 : Self.channel - Self.gap)
        let block = CGSize(width: (package.width - Self.inset * 2 - across) / CGFloat(columns),
                           height: (package.height - Self.inset * 2 - down) / CGFloat(rows))
        let lit = Int((min(max(load, 0), 1) * Double(cores)).rounded())
        ZStack {
            ChipLegs(leg: Self.leg)
                .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.4),
                                              Color(red: 0.72, green: 0.55, blue: 0.22)],
                                     startPoint: .top, endPoint: .bottom))
            ChipFace()
                .frame(width: package.width, height: package.height)
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    if row > 0 {
                        Color.clear.frame(height: row == rowSplit ? Self.channel : Self.gap)
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { column in
                            if column > 0 {
                                Color.clear.frame(width: column == columnSplit ? Self.channel : Self.gap)
                            }
                            let index = row * columns + column
                            if index < cores {
                                GPUBlock(isLit: index < lit, colors: colors)
                                    .frame(width: block.width, height: block.height)
                            } else {
                                Color.clear.frame(width: block.width, height: block.height)
                            }
                        }
                    }
                }
            }
            label
        }
        .frame(width: size.width, height: size.height)
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: lit)
    }

    /// "GPU", set in the CPU chip's silver, with a dark halo so it reads over lit cores
    /// and dark ones alike.
    private var label: some View {
        Text("GPU")
            .font(.system(size: 32, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(ChipGraphic.silver)
            .shadow(color: .black.opacity(0.7), radius: 3)
            .shadow(color: .black.opacity(0.4), radius: 8)
    }
}

/// A packaged chip's legs: short pins standing off all four edges of a package inset
/// `leg` into the rect, each running a point under the package so none floats.
private struct ChipLegs: Shape {
    let leg: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pitch: CGFloat = 8
        let width: CGFloat = 2.5
        let margin: CGFloat = 8
        var x = rect.minX + leg + margin
        while x <= rect.maxX - leg - margin {
            path.addRect(CGRect(x: x - width / 2, y: rect.minY, width: width, height: leg + 1))
            path.addRect(CGRect(x: x - width / 2, y: rect.maxY - leg - 1, width: width, height: leg + 1))
            x += pitch
        }
        var y = rect.minY + leg + margin
        while y <= rect.maxY - leg - margin {
            path.addRect(CGRect(x: rect.minX, y: y - width / 2, width: leg + 1, height: width))
            path.addRect(CGRect(x: rect.maxX - leg - 1, y: y - width / 2, width: leg + 1, height: width))
            y += pitch
        }
        return path
    }
}

/// One GPU core on the die: a dark block with a hairline edge, filled and glowing in
/// the card's colour while lit. All but square-cornered.
private struct GPUBlock: View {
    let isLit: Bool
    let colors: [Color]

    var body: some View {
        let block = RoundedRectangle(cornerRadius: 0.5, style: .continuous)
        ZStack {
            block.fill(Color.white.opacity(0.07))
            if isLit {
                block.fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: colors[0].opacity(0.6), radius: 2)
            }
            block.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        }
    }
}

/// The face Apple draws its chips with, shared by the CPU and the GPU: a square,
/// sharp-cornered die in near-black, a faint diagonal sheen across its top-left, and a
/// bright bevel along its edge.
///
/// A couple of shades lighter in dark appearance, with a brighter bevel all round: the
/// near-black that stands out on a white card all but disappears into a dark one.
private struct ChipFace: View {
    private static func shade(light: CGFloat, dark: CGFloat, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: appearance.isDark ? dark : light, alpha: alpha)
        })
    }

    private static let top = shade(light: 0.17, dark: 0.27)
    private static let bottom = shade(light: 0.07, dark: 0.15)
    private static let bevelLight = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(white: 1, alpha: appearance.isDark ? 0.5 : 0.32)
    })
    private static let bevelShadow = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(white: 1, alpha: appearance.isDark ? 0.16 : 0.04)
    })
    private static let bevelEnd = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(white: 1, alpha: appearance.isDark ? 0.3 : 0.14)
    })

    var body: some View {
        let face = Rectangle()
        ZStack {
            face.fill(LinearGradient(colors: [Self.top, Self.bottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            face.fill(LinearGradient(colors: [.white.opacity(0.07), .clear],
                                     startPoint: .topLeading, endPoint: .center))
            face.strokeBorder(LinearGradient(colors: [Self.bevelLight, Self.bevelShadow, Self.bevelEnd],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1)
        }
    }
}

/// A memory module with what is free printed on it, filled from the left with what is
/// in use. One board: the gold contacts sit along its bottom edge, which the key notch
/// cuts into, and only the part above them fills. Dark in both appearances, like the
/// chip.
private struct MemoryGraphic: View {
    /// Printed across the module: what is free.
    let label: String?
    let fraction: Double
    let load: Color

    /// The depth of the contact strip along the board's bottom edge.
    private static let connector: CGFloat = 8

    var body: some View {
        let board = NotchedBoard(edge: .bottom, cornerRadius: 4, notchFraction: 0.42,
                                 notchOffset: -4, notchLength: 8, notchDepth: Self.connector)
        // The part above the contacts: square along its foot, where it runs on into them.
        let face = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 4, bottomLeading: 0,
                                                             bottomTrailing: 0, topTrailing: 4),
                                          style: .continuous)
        ZStack {
            board.fill(BoardFinish.gradient)
            VStack(spacing: 0) {
                ZStack {
                    FillFromLeading(fraction: fraction)
                        .fill(LinearGradient(colors: [load.opacity(0.6), load.opacity(0.2)],
                                             startPoint: .leading, endPoint: .trailing))
                        .clipShape(face)
                    LevelEdge(fraction: fraction, axis: .horizontal).fill(load).clipShape(face)
                    // The memory packages, eight across as on a module.
                    HStack(spacing: 4) {
                        ForEach(0..<8, id: \.self) { _ in BoardPackage() }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 5)
                    Text(label ?? MetricFormatter.unavailable)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.72)],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.55), radius: 2)
                }
                MemoryContacts()
                    .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.4),
                                                  Color(red: 0.72, green: 0.55, blue: 0.22)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(.top, 1)
                    .padding(.bottom, 1.5)
                    .frame(height: Self.connector)
            }
            board.stroke(BoardFinish.edge, lineWidth: 1)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

/// An M.2 SSD: one long dark board with the edge connector's gold pins at its left end,
/// which the key notch cuts into, the controller and three flash packages along the
/// rest, and the half-round cut for its screw at the far end.
///
/// The board is the meter, as the memory module is: everything right of the connector
/// fills from the left with how full the disk is, and the controller and flash packages
/// sit on top of the fill, so it still reads as a drive. The connector stays gold
/// whatever the level.
private struct SSDGraphic: View {
    let fraction: Double
    let colors: [Color]
    /// Printed across the packages, as the memory module's capacity is.
    var label: String?

    /// The depth of the connector at the board's left end.
    private static let connector: CGFloat = 9

    var body: some View {
        let board = NotchedBoard(edge: .leading, cornerRadius: 3, notchFraction: 0.3,
                                 notchOffset: -1, notchLength: 6, notchDepth: Self.connector)
        // The part right of the connector: square at its left, where it runs on into it.
        let face = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 0,
                                                             bottomTrailing: 3, topTrailing: 3),
                                          style: .continuous)
        ZStack {
            board.fill(BoardFinish.gradient)
            HStack(spacing: 0) {
                SSDPins()
                    .fill(LinearGradient(colors: [Color(red: 0.72, green: 0.55, blue: 0.22),
                                                  Color(red: 0.93, green: 0.78, blue: 0.4)],
                                         startPoint: .leading, endPoint: .trailing))
                    .padding(.leading, 1)
                    .padding(.trailing, 1.5)
                    .frame(width: Self.connector)
                ZStack {
                    FillFromLeading(fraction: fraction)
                        .fill(LinearGradient(colors: [colors[0].opacity(0.65),
                                                      colors[colors.count - 1].opacity(0.25)],
                                             startPoint: .leading, endPoint: .trailing))
                        .clipShape(face)
                    LevelEdge(fraction: fraction, axis: .horizontal).fill(colors[0]).clipShape(face)
                    HStack(spacing: 5) {
                        BoardPackage().frame(width: 22, height: 22)
                        ForEach(0..<3, id: \.self) { _ in
                            BoardPackage().frame(height: 30)
                        }
                    }
                    .padding(.leading, 5)
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
                    // The screw's half-round cut, in the card's own colour so it reads as
                    // a notch out of the board.
                    HStack {
                        Spacer()
                        Circle().fill(BentoCard<EmptyView>.surface).frame(width: 10, height: 10)
                            .offset(x: 5)
                    }
                    if let label {
                        Text(label)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.72)],
                                                            startPoint: .top, endPoint: .bottom))
                            .shadow(color: .black.opacity(0.55), radius: 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            board.stroke(BoardFinish.edge, lineWidth: 1)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

/// The dark board finish the memory module and the SSD share, and the hairline that
/// keeps either one clear of a dark card.
private enum BoardFinish {
    static let gradient = LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)],
                                         startPoint: .top, endPoint: .bottom)
    static let edge = Color.white.opacity(0.16)
}

/// A chip package on a board: a dark translucent block with a light hairline edge.
///
/// Over the bare board it reads as a darker chip outlined in light; over a fill, as a
/// darker shade of the fill with the same edge, so it stays clear on both. That is what
/// a multiply blend would give, drawn as plain translucency so it renders the same
/// everywhere the panel is drawn.
private struct BoardPackage: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        shape.fill(Color.black.opacity(0.32))
            .overlay(shape.strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75))
    }
}

/// A board's outline: rounded corners, with the key notch cut into one edge, the
/// bottom of a memory module or the left end of an M.2 drive. The notch starts at
/// `notchFraction` along that edge, moved by `notchOffset` points, so it lines up with
/// the gap the contacts leave, and runs `notchDepth` into the board, the depth of the
/// connector. One path, so the fill and the outline both follow the notch.
private struct NotchedBoard: Shape {
    enum Edge { case bottom, leading }

    let edge: Edge
    let cornerRadius: CGFloat
    let notchFraction: CGFloat
    let notchOffset: CGFloat
    let notchLength: CGFloat
    let notchDepth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius
        switch edge {
        case .bottom:
            let start = rect.minX + rect.width * notchFraction + notchOffset
            let end = start + notchLength
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                        tangent2End: CGPoint(x: end, y: rect.maxY), radius: r)
            path.addLine(to: CGPoint(x: end, y: rect.maxY))
            path.addLine(to: CGPoint(x: end, y: rect.maxY - notchDepth))
            path.addLine(to: CGPoint(x: start, y: rect.maxY - notchDepth))
            path.addLine(to: CGPoint(x: start, y: rect.maxY))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        case .leading:
            let start = rect.minY + rect.height * notchFraction + notchOffset
            let end = start + notchLength
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.minX, y: end), radius: r)
            path.addLine(to: CGPoint(x: rect.minX, y: end))
            path.addLine(to: CGPoint(x: rect.minX + notchDepth, y: end))
            path.addLine(to: CGPoint(x: rect.minX + notchDepth, y: start))
            path.addLine(to: CGPoint(x: rect.minX, y: start))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        }
        path.closeSubpath()
        return path
    }
}

/// The edge connector: gold fingers stacked down the board's end, sized and spaced like
/// the memory module's contacts, broken a third of the way down by the key notch.
private struct SSDPins: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pitch: CGFloat = 4
        let notch = (rect.minY + rect.height * 0.3 - 1)...(rect.minY + rect.height * 0.3 + pitch + 1)
        var y = rect.minY + 3
        while y <= rect.maxY - 4 {
            if !notch.contains(y) {
                path.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: 2))
            }
            y += pitch
        }
        return path
    }
}

/// A battery at the proportions of the system glyph, large: an outlined body and a
/// terminal, the charge inset inside it.
struct BatteryGraphic: View {
    let fraction: Double
    let isCharging: Bool
    let charge: Color
    /// Strokes, radii and the bolt at a fraction of their full size, for a smaller card.
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 2 * scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                    .strokeBorder(Design.Palette.tertiaryText, lineWidth: 2.5 * scale)
                FillFromLeading(fraction: fraction)
                    .fill(charge)
                    .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
                    .padding(5 * scale)
                if isCharging {
                    // In the label colour with a halo of the card's, so it stands out over
                    // the charge and over the empty part alike, in either appearance.
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 19 * scale, weight: .bold))
                        .foregroundStyle(Design.Palette.primaryText)
                        .shadow(color: BentoCard<EmptyView>.surface, radius: 1)
                        .shadow(color: BentoCard<EmptyView>.surface, radius: 1)
                }
            }
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 0,
                                                      bottomTrailing: 3 * scale, topTrailing: 3 * scale))
                .fill(Design.Palette.tertiaryText)
                .frame(width: 4 * scale, height: 13 * scale)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

/// A thermometer standing up: a bulb at the foot, a tube with graduations, the column
/// rising from the bulb to the reading.
struct ThermometerGraphic: View {
    let fraction: Double
    let colors: [Color]
    /// Tube, bulb and scale at a fraction of their full size, for a smaller tile.
    var scale: CGFloat = 1

    var body: some View {
        let tube = Capsule(style: .continuous)
        let mercury = LinearGradient(colors: colors.reversed(), startPoint: .top, endPoint: .bottom)
        VStack(spacing: -6 * scale) {
            ZStack {
                tube.fill(colors[0].opacity(0.2))
                FillFromBottom(fraction: fraction).fill(mercury).clipShape(tube)
            }
            .frame(width: 12 * scale)
            .overlay(alignment: .trailing) {
                ZStack {
                    ThermometerScale(danger: false).fill(Design.Palette.tertiaryText)
                    ThermometerScale(danger: true).fill(Color(nsColor: .systemRed))
                }
                .frame(width: 6 * scale)
                .padding(.vertical, 6 * scale)
                .offset(x: 10 * scale)
            }
            Circle().fill(colors[0]).frame(width: 28 * scale, height: 28 * scale)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

// MARK: - Shape primitives

/// The curved corner a card is resized by, the way Control Center draws it.
private struct ResizeCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// The bottom `fraction` of a rect, animatable so a new reading rises rather than jumps.
private struct FillFromBottom: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let height = rect.height * min(max(fraction, 0), 1)
        return Path(CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height))
    }
}

/// The leading `fraction` of a rect.
private struct FillFromLeading: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY,
                    width: rect.width * min(max(fraction, 0), 1), height: rect.height))
    }
}

/// A bright line where a fill stops: across the top of a fill rising from the bottom,
/// or down the end of one growing from the leading edge.
private struct LevelEdge: Shape {
    var fraction: Double
    let axis: Axis
    var thickness: CGFloat = 1.5

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let level = min(max(fraction, 0), 1)
        guard level > 0 else { return Path() }
        switch axis {
        case .vertical:
            let y = rect.maxY - rect.height * level
            return Path(CGRect(x: rect.minX, y: y, width: rect.width, height: thickness))
        case .horizontal:
            let x = rect.minX + rect.width * level
            return Path(CGRect(x: x - thickness, y: rect.minY, width: thickness, height: rect.height))
        }
    }
}

/// Contacts along a memory module's edge, broken by the off-centre key notch.
private struct MemoryContacts: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notch = (rect.minX + rect.width * 0.42 - 4)...(rect.minX + rect.width * 0.42 + 4)
        var x = rect.minX + 6
        while x <= rect.maxX - 6 {
            if !notch.contains(x) {
                path.addRect(CGRect(x: x - 1, y: rect.minY, width: 2, height: rect.height))
            }
            x += 4.5
        }
        return path
    }
}

/// Graduations up the side of the tube: one every tenth, the half-way mark longer.
private struct ThermometerScale: Shape {
    /// The marks from `dangerFrom` up, or the ones below it.
    let danger: Bool

    /// The span the tube reads, matching how the card maps a temperature onto it.
    private static let lowest = 30
    private static let highest = 100
    private static let step = 2
    private static let dangerFrom = 90

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let span = CGFloat(Self.highest - Self.lowest)
        // A short tube keeps only the tens: marks every two degrees would run together.
        let step = rect.height < 80 ? 10 : Self.step
        for degrees in stride(from: Self.lowest + step, through: Self.highest, by: step)
        where (degrees >= Self.dangerFrom) == danger {
            let y = rect.maxY - rect.height * CGFloat(degrees - Self.lowest) / span
            // Every ten degrees runs the full width; the marks between are shorter.
            let width = degrees % 10 == 0 ? rect.width : rect.width * 0.55
            path.addRect(CGRect(x: rect.minX, y: y - 0.5, width: width, height: 1))
        }
        return path
    }
}

/// A process's icon: its app's own, or a gear for a process with no app around it.
struct ProcessIcon: View {
    let process: ProcessRow
    let size: CGFloat

    var body: some View {
        switch PanelAppIcon.icon(for: process) {
        case .bundle(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        case .executable:
            Image(systemName: "gearshape.fill")
                .font(.system(size: size * 0.72))
                .foregroundStyle(Design.Palette.secondaryText)
                .frame(width: size, height: size)
        }
    }
}

