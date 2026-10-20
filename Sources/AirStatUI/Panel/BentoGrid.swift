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
    /// Names each card's design and size under the pointer, for the gallery.
    var labelsSizes = false
    /// Which of the two arrangements this grid draws and edits: Bento's or Bento Small's.
    var arrangement: BentoArrangement = .regular

    private static let inset: CGFloat = 12
    private static let gap: CGFloat = 10
    /// One square cell. Six across, with the gaps and the inset, is 734 wide.
    private static let cell: CGFloat = 110
    static func width(for arrangement: BentoArrangement) -> CGFloat {
        inset * 2 + span(arrangement.columns)
    }
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
    /// The card under the pointer in the gallery, which shows its design's name.
    @State private var labelled: UUID?
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

    private var tiles: [BentoTile] { working ?? showing ?? settings.settings[keyPath: arrangement.tiles] }
    /// The arrangement can be changed: in the panel, and not in the gallery.
    private var canEdit: Bool { layout != nil && showing == nil }
    private var isEditing: Bool { layout?.isEditing == true }

    var body: some View {
        let tiles = self.tiles
        let packed = BentoLayout.pack(tiles, columns: arrangement.columns)
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                    if let placement = packed.placements[tile.id] {
                        placed(tile, frame: Self.frame(of: placement), index: index)
                    }
                }
            }
            .frame(width: Self.span(arrangement.columns), height: Self.span(max(packed.rows, 1)),
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
                if labelsSizes, labelled == tile.id {
                    Text("\(tile.variant.label) · \(tile.size.label)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(nsColor: .systemPurple)))
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .onHover { inside in
                guard labelsSizes else { return }
                if inside { labelled = tile.id } else if labelled == tile.id { labelled = nil }
            }
            .contextMenu {
                if !isEditing, canEdit {
                    Button("Edit Layout", systemImage: "square.grid.2x2") { layout?.beginEditing() }
                }
            }
            // Pressing and holding a module card starts arranging, as in Control Center.
            // Not the Settings card: holding its Quit must not quit on the way.
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
    /// the menu of its designs, and the corner it is resized by.
    private func editControls(_ tile: BentoTile, frame: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(moveGesture(tile, frame: frame))
            .overlay(alignment: .topLeading) {
                // Settings stays: its card is the panel's way to Settings and to Quit.
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
                if tile.kind.sizes.count > 1 { resizeHandle(tile) }
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
        let packed = BentoLayout.pack(list, columns: arrangement.columns).placements
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

    /// The corner a card is resized by: dragged, it snaps to the nearest size one of the
    /// card's designs comes in, and the cards around it flow out of the way.
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
                              working?[index].size != size,
                              let variant = tile.kind.variants.first(where: { $0.size == size }) else { return }
                        working?[index].variant = variant
                    }
            )
            .accessibilityLabel("Resize \(tile.kind.label)")
    }

    /// The card's designs, by what each shows and its size.
    private func options(_ tile: BentoTile) -> some View {
        Menu {
            Picker("Design", selection: binding(tile.id, \.variant, default: tile.variant)) {
                ForEach(tile.kind.variants, id: \.self) { variant in
                    Text("\(variant.label)   \(variant.size.label)").tag(variant)
                }
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
            Button { edit { $0 = arrangement.defaults } } label: {
                pill("arrow.counterclockwise", "Reset")
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Text("Drag to move · Drag a corner or use ••• for another design")
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
        var list = settings.settings[keyPath: arrangement.tiles]
        change(&list)
        let sanitized = BentoLayout.sanitized(list)
        settings.update { [arrangement] in $0[keyPath: arrangement.tiles] = sanitized }
    }

    private func commit() {
        guard let working else { return }
        let sanitized = BentoLayout.sanitized(working)
        settings.update { [arrangement] in $0[keyPath: arrangement.tiles] = sanitized }
        self.working = nil
    }

    // MARK: Cards

    @ViewBuilder
    private func tileView(_ tile: BentoTile, size: CGSize) -> some View {
        switch tile.variant {
        case .settings, .settingsTall, .settingsWide: settingsCard(size: size)
        case .cpuChip: cpu
        case .cpuChipSmall: cpuChipSmall
        case .cpuLoad: cpuLoad
        case .cpuChipHistory: cpuChipHistory
        case .memoryModule: memory
        case .memoryStick: memoryModuleCard
        case .memoryPressure: memoryPressure
        case .memoryWide: memoryWide
        case .gpuDie: gpu
        case .gpuDieSmall: gpuDieSmall
        case .gpuLoad: gpuLoad
        case .gpuDieHistory: gpuDieHistory
        case .networkSpeeds: network
        case .networkSpeedsSmall: networkSpeedsSmall
        case .networkHistory: networkHistory
        case .diskDrive: disk
        case .diskSpace: diskSpace
        case .diskHistory: diskHistory
        case .batteryCharge: battery
        case .batteryInside: batteryInside
        case .batteryHistory: batteryHistory
        case .batteryChargeHistory: batteryChargeHistory
        case .thermalThermometer: thermal
        case .thermalSmall: thermalSmall
        case .thermalSensors: thermalSensors
        case .thermalFans: thermalFans
        case .thermalCooling: thermalCooling
        case .systemAbout: system
        case .systemUptime: systemUptime
        case .systemDetails: systemDetails
        }
    }

    // MARK: The designed cards

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
        // No header: the die says it is the GPU, and its cores how many and how busy.
        card(.gpu, width: Self.span(2), height: Self.span(2), header: nil) {
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

    // MARK: CPU designs

    /// The chip filled by its load, the load over it. At this size the cores would be
    /// too small to read one by one, so the whole chip says how busy it is.
    private var cpuChipSmall: some View {
        let box = Self.box(.cpuChipSmall, header: true)
        return card(.cpuChipSmall, header: CardHeader("CPU", cpuLoadReading)) {
            fit(AnyView(chipLoad), native: CGSize(width: 140, height: 140), in: box)
        }
    }

    /// The chip filled by its load, beside the load and a bar each for the two kinds of
    /// core.
    private var cpuLoad: some View {
        let cpu = engine.cpu.value
        return card(.cpuLoad, header: nil) {
            HStack(spacing: Design.Space.l) {
                fit(AnyView(chipLoad), native: CGSize(width: 140, height: 140), in: CGSize(width: 78, height: 78))
                VStack(alignment: .leading, spacing: Design.Space.s) {
                    bigNumber(.cpu, cpuLoadReading, size: 28)
                    if let p = cpu?.performanceBusy, let e = cpu?.efficiencyBusy {
                        meterRow("P", p, colors: palette(.cpu), labelWidth: 10)
                        meterRow("E", e, colors: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)],
                                 labelWidth: 10)
                    } else if let cpu {
                        meterRow("User", cpu.total.user, colors: palette(.cpu), labelWidth: 30)
                        meterRow("Sys", cpu.total.system, colors: palette(.cpu), labelWidth: 30)
                    }
                }
            }
        }
    }

    /// The chip in one half; in the other its load beside its history, over the busiest
    /// processes by name.
    private var cpuChipHistory: some View {
        let box = Self.box(.cpuChipHistory, header: true)
        let half = Self.half(box)
        return card(.cpuChipHistory, header: cpuHeader) {
            halves(box) {
                fit(AnyView(chip), native: CGSize(width: 140, height: 140), in: CGSize(width: half, height: box.height))
            } right: {
                VStack(alignment: .leading, spacing: Design.Space.m) {
                    HStack(spacing: Design.Space.m) {
                        bigNumber(.cpu, cpuLoadReading, size: 32, fitting: half * 0.4)
                        sparkline(.cpu, height: 46)
                    }
                    busiestList
                }
            }
        }
    }

    // MARK: Memory designs

    /// The module alone, with what is free printed on it.
    private var memoryModuleCard: some View {
        let box = Self.box(.memoryStick, header: true)
        return card(.memoryStick, header: memoryHeader) {
            fit(AnyView(memoryStick), native: CGSize(width: 200, height: 56), in: box)
        }
    }

    /// Memory pressure as a ring, coloured the way Activity Monitor colours it.
    private var memoryPressure: some View {
        let memory = engine.memory.value
        let colours = memory.map { Self.pressureColors($0.memoryPressure) } ?? palette(.memory)
        return card(.memoryPressure, header: CardHeader("Memory")) {
            VStack(spacing: Design.Space.xs) {
                Ring(fraction: memory?.pressureFraction ?? 0, colors: colours, lineWidth: 7)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(memory.map { formatter.percent($0.pressureFraction) } ?? MetricFormatter.unavailable)
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(Design.Palette.primaryText)
                    }
                Text(memory.map { "\($0.memoryPressure.label) pressure" } ?? "Pressure")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(colours[0])
                    .lineLimit(1)
            }
        }
    }

    /// The module in one half with the pressure and swap under it; the biggest users in
    /// the other.
    private var memoryWide: some View {
        let box = Self.box(.memoryWide, header: true)
        let memory = engine.memory.value
        return card(.memoryWide, header: memoryHeader) {
            halves(box) {
                VStack(spacing: Design.Space.m) {
                    fit(AnyView(memoryStick), native: CGSize(width: 200, height: 56),
                        in: CGSize(width: Self.half(box), height: 64))
                    if let memory {
                        VStack(spacing: Design.Space.xs) {
                            HStack {
                                Text("Pressure").foregroundStyle(Design.Palette.secondaryText)
                                Spacer(minLength: 0)
                                Text(memory.memoryPressure.label)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Self.pressureColors(memory.memoryPressure)[0])
                            }
                            Bar(fraction: memory.pressureFraction, colors: Self.pressureColors(memory.memoryPressure))
                                .frame(height: 5)
                            HStack {
                                Text("Swap").foregroundStyle(Design.Palette.secondaryText)
                                Spacer(minLength: 0)
                                Text(memory.swapTotalBytes > 0
                                     ? "\(formatter.memory(memory.swapUsedBytes)) of \(formatter.memory(memory.swapTotalBytes))"
                                     : formatter.memory(memory.swapUsedBytes))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Design.Palette.primaryText)
                            }
                            .padding(.top, Design.Space.xs)
                            Bar(fraction: memory.swapTotalBytes > 0
                                    ? Double(memory.swapUsedBytes) / Double(memory.swapTotalBytes) : 0,
                                colors: palette(.memory))
                                .frame(height: 5)
                        }
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .padding(.horizontal, Design.Space.xs)
                    }
                }
            } right: {
                memoryList
            }
        }
    }

    // MARK: GPU designs

    /// The die alone, its lit cores the load.
    private var gpuDieSmall: some View {
        let box = Self.box(.gpuDieSmall, header: false)
        return card(.gpuDieSmall, header: nil) {
            fit(AnyView(gpuDie(CGSize(width: 200, height: 106))), native: CGSize(width: 200, height: 106), in: box)
        }
    }

    /// The die beside its load, and a bar for how much of the memory it may use it holds.
    private var gpuLoad: some View {
        let device = engine.gpu.value?.primary
        return card(.gpuLoad, header: nil) {
            HStack(spacing: Design.Space.l) {
                fit(AnyView(gpuDie(CGSize(width: 200, height: 106))), native: CGSize(width: 200, height: 106),
                    in: CGSize(width: 104, height: 64))
                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    bigNumber(.gpu, gpuLoadReading, size: 26)
                    if let used = device?.vramUsedBytes, let total = device?.vramTotalBytes, total > 0 {
                        Text("Memory")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Design.Palette.secondaryText)
                        Bar(fraction: Double(used) / Double(total), colors: palette(.gpu))
                            .frame(height: 5)
                    }
                }
            }
        }
    }

    /// The die in one half; in the other its load beside its history, over the meters.
    private var gpuDieHistory: some View {
        let box = Self.box(.gpuDieHistory, header: false)
        let half = Self.half(box)
        return card(.gpuDieHistory, header: nil) {
            halves(box) {
                fit(AnyView(gpuDie(CGSize(width: 200, height: 106))), native: CGSize(width: 200, height: 106),
                    in: CGSize(width: half, height: box.height))
            } right: {
                VStack(alignment: .leading, spacing: Design.Space.m) {
                    HStack(spacing: Design.Space.m) {
                        bigNumber(.gpu, gpuLoadReading, size: 32, fitting: half * 0.4)
                        sparkline(.gpu, height: 46)
                    }
                    gpuMeters
                }
            }
        }
    }

    // MARK: Network designs

    /// The symbol over both directions, small. No room for the network's name as well.
    private var networkSpeedsSmall: some View {
        let box = Self.box(.networkSpeedsSmall, header: false)
        return card(.networkSpeedsSmall, header: nil) {
            VStack(spacing: Design.Space.s) {
                Image(systemName: networkSymbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(gradient(.network))
                networkRates(size: 15, fitting: box.width)
            }
        }
    }

    /// The symbol and both directions, and the download's history under them.
    private var networkHistory: some View {
        let box = Self.box(.networkHistory, header: networkHeader != nil)
        return card(.networkHistory, header: networkHeader) {
            VStack(spacing: Design.Space.m) {
                HStack(spacing: Design.Space.xl) {
                    Image(systemName: networkSymbolName)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(gradient(.network))
                    networkRates()
                }
                sparkline(.network, height: max(box.height - 64, 40))
            }
        }
    }

    // MARK: SSD designs

    /// How full the drive is, as a ring, with what is left under it.
    private var diskSpace: some View {
        let root = engine.disk.value?.rootVolume
        let used = root.map { $0.totalBytes > 0 ? 1 - Double($0.availableBytes) / Double($0.totalBytes) : 0 }
        return card(.diskSpace, header: diskHeader) {
            VStack(spacing: Design.Space.xs) {
                Ring(fraction: used ?? 0, colors: palette(.disk), lineWidth: 7)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(used.map { formatter.percent($0) } ?? MetricFormatter.unavailable)
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(Design.Palette.primaryText)
                    }
                Text(root.map { "\(formatter.storage($0.availableBytes)) free" } ?? "SSD")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Design.Palette.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    /// The drive and its rates, and the reads' history under them.
    private var diskHistory: some View {
        let box = Self.box(.diskHistory, header: true)
        let drive = Self.fitted(CGSize(width: 200, height: 44), in: CGSize(width: box.width, height: 60))
        return card(.diskHistory, header: diskHeader) {
            VStack(spacing: Design.Space.s) {
                fit(AnyView(ssd), native: CGSize(width: 200, height: 44), in: CGSize(width: box.width, height: 60))
                diskRates
                sparkline(.disk, height: max(box.height - drive.height - 29, 30))
            }
        }
    }

    // MARK: Battery designs

    /// The charge written inside the battery, and how long it lasts under it.
    private var batteryInside: some View {
        card(.batteryInside, header: nil) {
            VStack(spacing: Design.Space.s) {
                fit(AnyView(batteryWithCharge), native: CGSize(width: 86, height: 40),
                    in: CGSize(width: 94, height: 46))
                Text(batteryState ?? "")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Design.Palette.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    /// A smaller battery beside its charge, and the charge's history under them.
    private var batteryHistory: some View {
        let box = Self.box(.batteryHistory, header: false)
        return card(.batteryHistory, header: nil) {
            VStack(spacing: Design.Space.m) {
                HStack(spacing: Design.Space.l) {
                    batteryObject.frame(width: 86, height: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        bigNumber(.battery, batteryReading, size: 30, colors: batteryColors)
                        Text(batteryState ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Design.Palette.secondaryText)
                            .lineLimit(1)
                    }
                }
                sparkline(.battery, height: max(box.height - 62, 40))
            }
        }
    }

    /// The battery with its charge inside, beside the charge's history.
    private var batteryChargeHistory: some View {
        let box = Self.box(.batteryChargeHistory, header: false)
        return card(.batteryChargeHistory, header: nil) {
            HStack(spacing: Design.Space.l) {
                VStack(spacing: Design.Space.s) {
                    fit(AnyView(batteryWithCharge), native: CGSize(width: 86, height: 40),
                        in: CGSize(width: 90, height: 42))
                    Text(batteryState ?? "")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Design.Palette.secondaryText)
                        .lineLimit(1)
                }
                sparkline(.battery, height: box.height - 10)
            }
        }
    }

    // MARK: Temperature designs

    /// A small thermometer beside the reading.
    private var thermalSmall: some View {
        card(.thermalSmall, header: thermalHeader) {
            HStack(spacing: Design.Space.m) {
                ThermometerGraphic(fraction: Self.thermometerLevel(engine.thermal.value?.cpuCelsius),
                                   colors: Self.heat, scale: 0.45)
                    .frame(width: 14, height: 63)
                bigNumber(.thermal, temperatureReading ?? engine.thermal.value?.pressure.label,
                          size: 24, fitting: 64)
            }
        }
    }

    /// A thermometer for every part with a sensor: the CPU, the GPU, the SSD, the battery.
    private var thermalSensors: some View {
        let thermal = engine.thermal.value
        let power = engine.power.value
        let readings: [(String, Double?)] = [
            ("CPU", thermal?.cpuCelsius), ("GPU", thermal?.gpuCelsius),
            ("SSD", Self.hottest(thermal, .storage)),
            ("Battery", power?.temperatureCelsius ?? Self.hottest(thermal, .battery)),
        ]
        let shown = readings.compactMap { name, celsius in celsius.map { (name, $0) } }
        return card(.thermalSensors, header: nil) {
            if shown.isEmpty {
                bigNumber(.thermal, thermal?.pressure.label, size: 20)
            } else {
                HStack(spacing: 0) {
                    ForEach(shown, id: \.0) { name, celsius in
                        VStack(spacing: Design.Space.xs) {
                            ThermometerGraphic(fraction: Self.thermometerLevel(celsius), colors: Self.heat, scale: 0.75)
                                .frame(width: 22, height: 105)
                            Text(formatter.temperature(celsius))
                                .font(.system(size: 15, weight: .bold).monospacedDigit())
                                .foregroundStyle(gradient(.thermal))
                                .contentTransition(.numericText())
                            Text(name)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Design.Palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// The fans, spinning at their real pace, and how fast each is going.
    private var thermalFans: some View {
        let fans = Array((engine.thermal.value?.fans ?? []).prefix(2))
        return card(.thermalFans, header: nil) {
            if fans.isEmpty {
                VStack(spacing: Design.Space.xs) {
                    Image(systemName: "fan")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Design.Palette.tertiaryText)
                    Text("No fans")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Design.Palette.secondaryText)
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(fans) { fan in
                        VStack(spacing: Design.Space.xs) {
                            ZStack {
                                Circle().fill(Self.fanWell)
                                // Drawn at MacBook mode's size and scaled, so the hub
                                // and the blades keep their proportions.
                                fit(AnyView(SpinningFan(fraction: fan.loadFraction ?? min(fan.currentRPM / 6000, 1),
                                                        isSpinning: fan.currentRPM >= 1)),
                                    native: CGSize(width: 128, height: 128), in: CGSize(width: 42, height: 42))
                            }
                            .frame(width: 46, height: 46)
                            VStack(spacing: 0) {
                                Text(fan.currentRPM < 1 ? "Off" : formatter.rpm(fan.currentRPM))
                                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                                    .foregroundStyle(LinearGradient(colors: [Color(nsColor: .systemCyan),
                                                                             Color(nsColor: .systemBlue)],
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(fan.name)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Design.Palette.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// The CPU's thermometer between the fans that cool it, heat pipes running from its
    /// bulb to each, as the parts sit in the machine; their readings in a row under them.
    private var thermalCooling: some View {
        let fans = engine.thermal.value?.fans ?? []
        let celsius = engine.thermal.value?.cpuCelsius
        let box = Self.box(.thermalCooling, header: false)
        // Laid out on the box's own points: the bulb and both fans on one line.
        let bulb: CGFloat = 112
        let columns: [CGFloat] = [box.width * 0.18, box.width / 2, box.width * 0.82]
        let copper = LinearGradient(colors: [Color(red: 0.9, green: 0.6, blue: 0.36),
                                             Color(red: 0.66, green: 0.38, blue: 0.2)],
                                    startPoint: .top, endPoint: .bottom)
        return card(.thermalCooling, header: nil) {
            ZStack(alignment: .topLeading) {
                if !fans.isEmpty {
                    Capsule().fill(copper)
                        .frame(width: columns[2] - columns[0], height: 8)
                        .position(x: box.width / 2, y: bulb)
                }
                ThermometerGraphic(fraction: Self.thermometerLevel(celsius), colors: Self.heat, scale: 0.85)
                    .frame(width: 26, height: 119)
                    .position(x: columns[1], y: bulb + 12.5 - 59.5)
                ForEach(Array(fans.prefix(2).enumerated()), id: \.offset) { index, fan in
                    coolingFan(fan, diameter: 62)
                        .position(x: columns[index == 0 ? 0 : 2], y: bulb)
                }
                coolingReading(temperatureReading ?? "—", "CPU", colors: palette(.thermal))
                    .position(x: columns[1], y: bulb + 44)
                ForEach(Array(fans.prefix(2).enumerated()), id: \.offset) { index, fan in
                    coolingReading(fan.currentRPM < 1 ? "Off" : formatter.rpm(fan.currentRPM), fan.name,
                                   colors: [Color(nsColor: .systemCyan), Color(nsColor: .systemBlue)])
                        .position(x: columns[index == 0 ? 0 : 2], y: bulb + 44)
                }
            }
            .frame(width: box.width, height: bulb + 62)
        }
    }

    private func coolingFan(_ fan: FanInfo, diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(Self.fanWell)
            fit(AnyView(SpinningFan(fraction: fan.loadFraction ?? min(fan.currentRPM / 6000, 1),
                                    isSpinning: fan.currentRPM >= 1)),
                native: CGSize(width: 128, height: 128),
                in: CGSize(width: diameter - 6, height: diameter - 6))
        }
        .frame(width: diameter, height: diameter)
    }

    private func coolingReading(_ value: String, _ label: String, colors: [Color]) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(gradient(colors))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Design.Palette.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: 76)
    }

    // MARK: System designs

    /// How long the Mac has been up.
    private var systemUptime: some View {
        card(.systemUptime, header: nil) {
            VStack(spacing: 2) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(gradient(.system))
                bigNumber(.system, engine.system.value.map { formatter.uptime($0.uptime) }, size: 24,
                          fitting: 94)
                Text("uptime")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
            }
        }
    }

    /// What About This Mac says: the model, the chip, the memory, the macOS, and the uptime.
    @ViewBuilder
    private var systemDetails: some View {
        let system = engine.system.value
        card(.systemDetails, header: nil) {
            if let system {
                let model = Self.model(system)
                VStack(spacing: Design.Space.s) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(gradient(.system))
                    VStack(spacing: 1) {
                        Text(model.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Design.Palette.primaryText)
                        Text(model.detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Design.Palette.secondaryText)
                    }
                    Rectangle().fill(Design.Palette.separator).frame(height: 1)
                    VStack(spacing: 3) {
                        detailRow("Chip", system.chipName)
                        detailRow("Memory", Self.marketingCapacity(system.totalMemoryBytes))
                        detailRow(system.osName, system.osVersion)
                        detailRow("Uptime", formatter.uptime(system.uptime))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, Design.Space.xs)
            } else {
                bigNumber(.system, nil, size: 24)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Design.Palette.secondaryText)
            Spacer(minLength: Design.Space.s)
            Text(value)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Design.Palette.primaryText)
        }
    }

    // MARK: Layout

    /// The room inside a design's card: under its header if it has one, inside its padding.
    private static func box(_ variant: BentoVariant, header: Bool) -> CGSize {
        CGSize(width: span(variant.size.columns) - 16, height: span(variant.size.rows) - (header ? 42 : 23))
    }

    private static func half(_ box: CGSize) -> CGFloat { (box.width - 16) / 2 }

    /// A four-cell-wide card split at the grid line between its second cell and its
    /// third, so both halves line up with the cards around it.
    private func halves<Left: View, Right: View>(_ box: CGSize, @ViewBuilder left: () -> Left,
                                                 @ViewBuilder right: () -> Right) -> some View {
        HStack(spacing: 16) {
            left().frame(width: Self.half(box))
            right().frame(width: Self.half(box), alignment: .leading)
        }
    }

    /// An object at its own proportions, as large as `box` allows.
    private func fit(_ object: AnyView, native: CGSize, in box: CGSize) -> some View {
        let size = Self.fitted(native, in: box)
        let scale = size.width / native.width
        return object
            .frame(width: native.width, height: native.height)
            .scaleEffect(scale)
            .frame(width: size.width, height: size.height)
    }

    /// The size an object is drawn at in `box`.
    private static func fitted(_ native: CGSize, in box: CGSize) -> CGSize {
        let scale = max(0.1, min(box.width / native.width, box.height / native.height, 2.5))
        return CGSize(width: native.width * scale, height: native.height * scale)
    }

    /// A label, a bar and its figure on one line: "P ▬▬▬▬── 38%".
    private func meterRow(_ label: String, _ fraction: Double, colors: [Color],
                          labelWidth: CGFloat) -> some View {
        HStack(spacing: Design.Space.s) {
            Text(label)
                .foregroundStyle(Design.Palette.secondaryText)
                .frame(width: labelWidth, alignment: .leading)
            Bar(fraction: fraction, colors: colors)
                .frame(height: 5)
            Text(formatter.percent(fraction))
                .foregroundStyle(Design.Palette.primaryText)
                .frame(width: 30, alignment: .trailing)
        }
        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
    }

    /// The module's recent history, in its colour. Where it has two directions, both, on
    /// one scale: the network's download in blue with its upload in orange behind it, the
    /// drive's reads in blue with its writes in orange, as the readings over them are.
    @ViewBuilder
    private func sparkline(_ module: PanelModule, height: CGFloat) -> some View {
        if let series = module.historySeries {
            let twoWay = series.secondary != nil
            let colour = twoWay ? Self.downColors[0] : palette(module)[0]
            Sparkline(ChartSeries(series.key, from: engine.history, tint: colour, domain: series.domain),
                      companion: series.secondary.map {
                          ChartSeries($0, from: engine.history, tint: Color(nsColor: .systemOrange))
                      },
                      settings: settings.settings.charts, height: height)
        }
    }

    private var cpuLoadReading: String? {
        engine.cpu.value.map { formatter.percent($0.total.busy) }
    }

    private var gpuLoadReading: String? {
        engine.gpu.value?.primary?.utilization.map { formatter.percent($0) }
    }

    private var networkSymbolName: String {
        let network = engine.network.value ?? engine.lastKnown.network.value
        return network?.wifi != nil || network == nil ? "wifi" : "network"
    }

    /// The battery with its charge written inside, in the label colour with a halo of the
    /// card's so it reads over the charge and the empty part alike, and a bolt before it
    /// while charging.
    private var batteryWithCharge: some View {
        let power = engine.power.value
        return ZStack {
            BatteryGraphic(fraction: (power?.percentage ?? 0) / 100, isCharging: false,
                           charge: batteryIsLow ? Color(nsColor: .systemRed) : palette(.battery)[0])
            HStack(spacing: 1) {
                if power?.isCharging == true {
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .heavy))
                }
                Text(batteryReading ?? MetricFormatter.unavailable)
                    .font(.system(size: 17, weight: .heavy).monospacedDigit())
            }
            .foregroundStyle(Design.Palette.primaryText)
            .shadow(color: BentoCard<EmptyView>.surface, radius: 1)
            .shadow(color: BentoCard<EmptyView>.surface, radius: 1)
            // Centred on the body, not on the body and its terminal.
            .offset(x: -3)
        }
    }

    private static let heat = [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)]

    /// The thermometer's scale: 30°C empty, 100°C full.
    private static func thermometerLevel(_ celsius: Double?) -> Double {
        celsius.map { min(max(($0 - 30) / 70, 0), 1) } ?? 0
    }

    private static func hottest(_ thermal: ThermalSnapshot?, _ category: SensorCategory) -> Double? {
        thermal?.sensors.filter { $0.category == category }.map(\.celsius).max()
    }

    /// The dark well a fan turns in, like the chip's face: an object, dark on either card.
    private static let fanWell = Color(nsColor: NSColor(name: nil) {
        NSColor(white: $0.isDark ? 0.2 : 0.16, alpha: 1)
    })

    /// Memory pressure in Activity Monitor's colours: green, then yellow, then red.
    static func pressureColors(_ level: MemoryPressureLevel) -> [Color] {
        switch level {
        case .normal: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)]
        case .warning: [Color(nsColor: .systemYellow), Color(nsColor: .systemOrange)]
        case .critical: [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)]
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
                           performanceColors: [.white, .white],
                           efficiencyColors: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)])
    }

    /// The chip without its cores, filled from the bottom by the whole CPU's load.
    private var chipLoad: some View {
        ChipGraphic(name: engine.system.value?.chipName, performance: [], efficiency: [],
                    performanceColors: [.white, .white], efficiencyColors: [],
                    load: engine.cpu.value?.total.busy ?? 0)
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
                             fraction: used ?? 0, load: palette(.memory)[0])
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

    @ViewBuilder
    private func gpuDie(_ size: CGSize) -> some View {
        let device = engine.gpu.value?.primary
        if let cores = device?.coreCount ?? engine.system.value?.gpuCoreCount, cores > 0 {
            GPUDie(cores: cores, load: device?.utilization ?? 0, colors: palette(.gpu),
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
                          colors: palette(.disk),
                          label: root.map { "\(formatter.storage($0.availableBytes)) free" })
    }

    private var diskRates: some View {
        HStack(spacing: Design.Space.xl) {
            diskRate("Read", engine.disk.value?.readBytesPerSecond,
                     symbol: "arrow.down.circle.fill", colors: Self.downColors)
            diskRate("Write", engine.disk.value?.writeBytesPerSecond,
                     symbol: "arrow.up.circle.fill", colors: Self.upColors)
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
            // Each line wraps rather than being cut short: every word of it is the point.
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
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Pieces

    /// The process list now, or the last one while the list re-establishes its baseline
    /// on opening, which the cards grey rather than leave empty.
    private var processList: (list: ProcessSnapshot, isLastKnown: Bool)? {
        if let current = engine.processes.value { return (current, false) }
        return engine.lastKnown.processes.value.map { ($0, true) }
    }

    /// Settings as a card, the whole card the button, with Quit small in its corner:
    /// the app was just opened, and a card-sized button to close it again was too much.
    private func settingsCard(size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        // The symbol alone: a gear needs no word under it.
        return Button(action: actions.openSettings) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(gradient(.system))
                .frame(width: size.width, height: size.height)
        }
        .buttonStyle(BentoActionStyle())
        .keyboardShortcut(",", modifiers: .command)
        .accessibilityLabel("Settings")
        .overlay(alignment: .topTrailing) {
            // Where the card's ••• sits in edit mode, which covers it while it cannot be used.
            Button(action: actions.quit) {
                Image(systemName: "power").font(.system(size: 9, weight: .heavy))
            }
            .buttonStyle(BentoQuitStyle())
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit Bento Stats")
            .padding(Design.Space.s)
        }
        .background(shape.fill(BentoCard<EmptyView>.surface))
        .clipShape(shape)
    }

    private func card<Content: View>(_ variant: BentoVariant, header: CardHeader?,
                                     @ViewBuilder content: () -> Content) -> some View {
        card(variant.kind.module ?? .system, width: Self.span(variant.size.columns),
             height: Self.span(variant.size.rows), header: header, content: content)
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

    /// A drive rate in the network's colours for the two directions: a read comes in to
    /// the Mac, blue and down, as a download does; a write goes out, red and up.
    private func diskRate(_ label: String, _ bytesPerSecond: Double?, symbol: String,
                          colors: [Color]) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(bytesPerSecond.map { formatter.diskRate($0) } ?? MetricFormatter.unavailable)
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(gradient(colors))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
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
    /// and chosen so the cards read as different things at a glance.
    private func palette(_ module: PanelModule) -> [Color] {
        Self.palette(module)
    }

    static func palette(_ module: PanelModule) -> [Color] {
        let pair: (NSColor, NSColor)
        switch module {
        case .cpu, .system: pair = (white, white)
        case .memory: pair = (.systemIndigo, .systemBlue)
        case .gpu: pair = (gpuOrange, gpuOrange)
        case .network: pair = (.systemOrange, .systemYellow)
        case .disk: pair = (.systemTeal, .systemMint)
        case .battery: pair = (.systemGreen, .systemMint)
        case .thermal: pair = (.systemRed, .systemOrange)
        case .processes: pair = (.systemPink, .systemRed)
        }
        return [Color(nsColor: pair.0), Color(nsColor: pair.1)]
    }

    /// White on the dark cards; on the light ones, where white would vanish, the text
    /// colour instead.
    private static let white = NSColor(name: nil) { $0.isDark ? .white : .labelColor }

    private static let gpuOrange = NSColor(srgbRed: 1, green: 0.573, blue: 0.188, alpha: 1)

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

extension MetricsEngine {
    /// Whether `module` is waiting for its first reading since sampling started, which
    /// for a collector that measures rates is the first sample after every pause.
    func isCollecting(_ module: PanelModule) -> Bool {
        switch module {
        case .cpu: cpu.failure == .pending
        case .memory: memory.failure == .pending
        case .gpu: gpu.failure == .pending
        case .network: network.failure == .pending
        case .disk: disk.failure == .pending
        case .battery: power.failure == .pending
        case .thermal: thermal.failure == .pending
        case .processes: processes.failure == .pending
        case .system: system.failure == .pending
        }
    }
}

// MARK: - Arrangements

/// The two bento arrangements, each with its own cards and its own width.
enum BentoArrangement: Sendable {
    case regular, small

    var columns: Int { self == .small ? BentoLayout.smallColumns : BentoLayout.columns }

    var tiles: WritableKeyPath<AirStatKit.Settings, [BentoTile]> {
        self == .small ? \.panel.bentoSmallTiles : \.panel.bentoTiles
    }

    /// What Reset goes back to.
    var defaults: [BentoTile] {
        self == .small ? BentoLayout.defaultSmallTiles : BentoLayout.defaultTiles
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

/// Quit, small in the Settings card's corner: red on a red tint at rest, solid red under
/// the pointer, so it is plain what it does before it is pressed.
private struct BentoQuitStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BentoQuitBody(configuration: configuration)
    }
}

private struct BentoQuitBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        let red = Color(nsColor: .systemRed)
        configuration.label
            .foregroundStyle(isHovering ? Color.white : red)
            .frame(width: 20, height: 20)
            .background(Circle().fill(isHovering ? red : red.opacity(0.16)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
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
    /// The whole CPU's load, filling the die from the bottom, in place of its cores.
    var load: Double? = nil

    private var loadColour: Color { performanceColors.first ?? .white }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ChipFace()
                if let load {
                    ZStack {
                        FillFromBottom(fraction: load)
                            .fill(LinearGradient(colors: [loadColour.opacity(0.12), loadColour.opacity(0.42)],
                                                 startPoint: .top, endPoint: .bottom))
                        LevelEdge(fraction: load, axis: .vertical, thickness: 2).fill(loadColour)
                    }
                    .frame(width: side, height: side)
                    .clipped()
                    lettering(side: side, scale: 0.9)
                } else if performance.isEmpty && efficiency.isEmpty {
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

/// A ring gauge, filling clockwise from the top in its gradient over a faint track: how
/// hard memory is pressed, how full the drive is.
private struct Ring: View {
    let fraction: Double
    let colors: [Color]
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Design.Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.001), 1))
                .stroke(AngularGradient(colors: colors + [colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

/// A slim bar filling from the left in its gradient.
private struct Bar: View {
    let fraction: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Design.Palette.track)
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
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

