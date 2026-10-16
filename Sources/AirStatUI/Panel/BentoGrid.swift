import SwiftUI
import AppKit
import AirStatKit

/// The bento style: every module as a card in a grid of mixed sizes, the way Apple lays
/// out what is new in a Mac.
///
/// One fixed composition rather than a flowing grid. A bento grid works when the big
/// cards are the ones that matter most and the small ones fill in around them, which is
/// a design decision, not something a layout algorithm makes:
///
///     ┌───────────┬───────────┐
///     │           │  Memory   │
///     │    CPU    ├─────┬─────┤
///     │           │ GPU │Disk │
///     ├───────────┼─────┼─────┤
///     │  Battery  │     │Proc │
///     ├───────────┤Temp ├─────┤
///     │  Network  │     │ Sys │
///     └───────────┴─────┴─────┘
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

    static let width: CGFloat = 460
    private static let inset: CGFloat = 12
    private static let gap: CGFloat = 10
    /// One of four columns.
    private static let unitWidth = (width - inset * 2 - gap * 3) / 4
    private static let unitHeight: CGFloat = 100
    private static let wide = unitWidth * 2 + gap
    private static let tall = unitHeight * 2 + gap

    private var formatter: MetricFormatter {
        MetricFormatter(settings: settings.settings.general)
    }

    var body: some View {
        VStack(spacing: Self.gap) {
            HStack(alignment: .top, spacing: Self.gap) {
                cpu
                VStack(spacing: Self.gap) {
                    memory
                    HStack(spacing: Self.gap) { gpu; disk }
                }
            }
            HStack(alignment: .top, spacing: Self.gap) {
                VStack(spacing: Self.gap) { battery; network }
                thermal
                VStack(spacing: Self.gap) { processes; system }
            }
        }
        .padding(Self.inset)
        .environment(\.metricFormatter, formatter)
    }

    // MARK: Cards

    private var cpu: some View {
        let busy = engine.cpu.value?.total.busy
        let system = engine.system.value
        return card(.cpu, width: Self.wide, height: Self.tall,
                    caption: system.map { "\($0.physicalCores)-core CPU" } ?? "CPU") {
            VStack(spacing: Design.Space.m) {
                ChipGraphic(name: system?.chipName, fraction: busy ?? 0, load: palette(.cpu)[0])
                    .frame(width: 112, height: 112)
                bigNumber(.cpu, busy.map { formatter.percent($0) }, size: 30)
            }
        }
    }

    private var memory: some View {
        let memory = engine.memory.value
        let used = memory.map { $0.totalBytes > 0 ? Double($0.usedBytes) / Double($0.totalBytes) : 0 }
        return card(.memory, width: Self.wide, height: Self.unitHeight,
                    caption: memory.map { "Memory · \(formatter.memory($0.usedBytes)) used" } ?? "Memory") {
            MemoryGraphic(capacity: memory.map { Self.marketingCapacity($0.totalBytes) },
                          fraction: used ?? 0, load: palette(.memory)[0])
                .frame(width: 176, height: 50)
        }
    }

    private var gpu: some View {
        let device = engine.gpu.value?.primary
        let cores = device?.coreCount ?? engine.system.value?.gpuCoreCount
        let load = device?.utilization
        return card(.gpu, width: Self.unitWidth, height: Self.unitHeight,
                    caption: load.map { "GPU · \(formatter.percent($0))" } ?? "GPU") {
            VStack(spacing: Design.Space.s) {
                numberWithUnit(.gpu, cores.map { formatter.count($0) }, unit: "cores", size: 28)
                LevelBar(fraction: load ?? 0, colors: palette(.gpu))
            }
        }
    }

    private var disk: some View {
        let root = engine.disk.value?.rootVolume
        // The number and its unit are set apart, as Apple sets "1TB", so the number can
        // be large without the unit crowding it.
        let parts = root.map { formatter.storage($0.availableBytes).split(separator: " ") }
        return card(.disk, width: Self.unitWidth, height: Self.unitHeight, caption: "free") {
            VStack(spacing: Design.Space.s) {
                numberWithUnit(.disk, parts?.first.map(String.init),
                               unit: parts.flatMap { $0.count > 1 ? String($0[1]) : nil } ?? "",
                               size: 28)
                // How full the disk is, the way Finder and System Settings draw storage,
                // from the same available space as the number above it so the two agree.
                LevelBar(fraction: root.map { $0.totalBytes > 0
                            ? 1 - Double($0.availableBytes) / Double($0.totalBytes) : 0 } ?? 0,
                         colors: palette(.disk))
            }
        }
    }

    private var battery: some View {
        let power = engine.power.value
        return card(.battery, width: Self.wide, height: Self.unitHeight,
                    caption: power.map(batteryCaption) ?? "Battery") {
            HStack(spacing: Design.Space.l) {
                if let power, !power.hasBattery {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(gradient(.battery))
                    bigNumber(.battery, "AC", size: 28)
                } else {
                    let fraction = (power?.percentage ?? 0) / 100
                    let isLow = power != nil && fraction <= 0.2 && power?.isCharging == false
                    BatteryGraphic(fraction: fraction, isCharging: power?.isCharging ?? false,
                                   charge: isLow ? Color(nsColor: .systemRed) : palette(.battery)[0])
                        .frame(width: 86, height: 40)
                    bigNumber(.battery, power?.percentage.map { formatter.percentValue($0) }, size: 30,
                              colors: isLow ? [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)] : nil)
                }
            }
        }
    }

    private var network: some View {
        let network = engine.network.value
        return card(.network, width: Self.wide, height: Self.unitHeight,
                    caption: network.map { $0.wifi?.ssid ?? $0.connectionType.label } ?? "Network") {
            // Upload over download, in Activity Monitor's colours for the two directions:
            // red going out, blue coming in.
            VStack(alignment: .leading, spacing: 0) {
                rate("arrow.up", network.map { formatter.networkRate($0.uploadBytesPerSecond) },
                     colors: [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)])
                rate("arrow.down", network.map { formatter.networkRate($0.downloadBytesPerSecond) },
                     colors: [Color(nsColor: .systemBlue), Color(nsColor: .systemCyan)])
            }
        }
    }

    private var thermal: some View {
        let thermal = engine.thermal.value
        let celsius = thermal?.cpuCelsius
        let caption = thermal.map { celsius == nil ? "No sensor" : "CPU · \($0.pressure.label)" }
        return card(.thermal, width: Self.unitWidth, height: Self.tall,
                    caption: caption ?? "Temperature") {
            VStack(spacing: Design.Space.m) {
                ThermometerGraphic(fraction: celsius.map { min(max(($0 - 30) / 70, 0), 1) } ?? 0,
                                   colors: palette(.thermal))
                    .frame(width: 30, height: 112)
                bigNumber(.thermal, celsius.map { formatter.temperature($0) } ?? thermal?.pressure.label,
                          size: celsius == nil ? 17 : 26)
            }
        }
    }

    private var processes: some View {
        let processes = engine.processes.value
        let top = processes?.processes.max { $0.cpuPercent < $1.cpuPercent }
        return card(.processes, width: Self.unitWidth, height: Self.unitHeight,
                    caption: top?.name ?? "processes") {
            VStack(spacing: 0) {
                bigNumber(.processes, processes.map { formatter.count($0.totalProcessCount) }, size: 28)
                Text("processes")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
            }
        }
    }

    private var system: some View {
        let system = engine.system.value
        return card(.system, width: Self.unitWidth, height: Self.unitHeight, caption: "uptime") {
            bigNumber(.system, system.map { formatter.uptime($0.uptime) }, size: 22)
        }
    }

    // MARK: Pieces

    private func card<Content: View>(_ module: PanelModule, width: CGFloat, height: CGFloat,
                                     caption: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        BentoCard(module: module, caption: caption, ring: palette(module)[0],
                  isActive: layout?.detailModule == module, layout: layout,
                  size: CGSize(width: width, height: height), content: content())
    }

    /// The card's reading, large and bold in the card's gradient. A spinner while the
    /// module waits for its first reading, a dash where there is none to give.
    @ViewBuilder
    private func bigNumber(_ module: PanelModule, _ text: String?, size: CGFloat,
                           colors: [Color]? = nil) -> some View {
        if text == nil, engine.isCollecting(module) {
            ProgressView().controlSize(.small).frame(height: size)
        } else {
            Text(text ?? MetricFormatter.unavailable)
                .font(.system(size: size, weight: .bold).monospacedDigit())
                .foregroundStyle(text == nil ? AnyShapeStyle(Design.Palette.tertiaryText)
                                             : AnyShapeStyle(gradient(colors ?? palette(module))))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
    }

    /// A large number with its unit beside it, small, on the same baseline.
    private func numberWithUnit(_ module: PanelModule, _ number: String?, unit: String,
                                size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.xxs) {
            bigNumber(module, number, size: size)
            if number != nil {
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Design.Palette.secondaryText)
            }
        }
    }

    private func rate(_ symbol: String, _ value: String?, colors: [Color]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.xs) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(gradient(colors))
                .frame(width: 16)
            bigNumber(.network, value, size: 21, colors: colors)
        }
    }

    private func batteryCaption(_ power: PowerSnapshot) -> String {
        guard power.hasBattery else { return "Power adapter" }
        if power.isCharging {
            return power.timeToFull.map { "Full in \(formatter.duration($0))" } ?? "Charging"
        }
        if power.isFullyCharged { return "Fully charged" }
        return power.timeToEmpty.map { "\(formatter.duration($0)) remaining" } ?? "On battery"
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
    private func palette(_ module: PanelModule) -> [Color] {
        if let custom = settings.settings.theme.color(for: module.requiredSource) {
            return [Color(themeColor: custom), Color(themeColor: custom)]
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

    /// Installed memory the way it is sold: 34,359,738,368 bytes is "32 GB", not the
    /// "34.4 GB" a decimal formatter makes of it.
    private static func marketingCapacity(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / Double(1 << 30)
        return "\(Int(gigabytes.rounded())) GB"
    }
}

// MARK: - Card

/// One card: its content centred, a caption under it. Reports the pointer the way a list
/// row does, so the detail opens beside the panel level with the card, and takes a ring
/// in its own colour while that detail is open.
private struct BentoCard<Content: View>: View {
    let module: PanelModule
    let caption: String
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
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Design.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Design.Space.m)
        .padding(.top, Design.Space.l)
        .padding(.bottom, Design.Space.m + 1)
        .frame(width: size.width, height: size.height)
        .background(shape.fill(Self.surface))
        .overlay {
            if isActive { shape.strokeBorder(ring, lineWidth: 2) }
        }
        .contentShape(shape)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onContinuousHover { phase in
            switch phase {
            case .active: layout?.rowHover?(module, frame)
            case .ended: layout?.rowHover?(module, nil)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Graphics

/// An Apple silicon package drawn the way Apple shows it: a square, sharp-cornered die
/// in near-black with a faint sheen and a bright bevel, the logo and chip in brushed
/// silver, and the tier — PRO, MAX, ULTRA — in its own gradient underneath.
///
/// The CPU's load rises over the face from the bottom as a translucent wash of blue
/// with a bright line at its level, under the lettering: the chip still reads as the
/// chip, the name stays crisp at any level, and how much of it is busy reads at a
/// glance from the line. The chip is drawn dark in both appearances: it is an object, and
/// Apple's chip is black on a white page too.
private struct ChipGraphic: View {
    /// "Apple M1 Max", or whatever the system reports for a chip that is not Apple's.
    let name: String?
    let fraction: Double
    let load: Color

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let face = Rectangle()
            ZStack {
                face.fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.07)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                // The sheen: a soft diagonal lift across the top-left of the die.
                face.fill(LinearGradient(colors: [.white.opacity(0.07), .clear],
                                         startPoint: .topLeading, endPoint: .center))
                FillFromBottom(fraction: fraction)
                    .fill(LinearGradient(colors: [load.opacity(0.55), load.opacity(0.12)],
                                         startPoint: .bottom, endPoint: .top))
                LevelEdge(fraction: fraction, axis: .vertical).fill(load)
                face.strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.04),
                                                          .white.opacity(0.14)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1)
                lettering(side: side)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }

    private static let silver = LinearGradient(colors: [Color(white: 0.97), Color(white: 0.66)],
                                               startPoint: .top, endPoint: .bottom)

    @ViewBuilder
    private func lettering(side: CGFloat) -> some View {
        if let name, name.hasPrefix("Apple ") {
            // "Apple M1 Max" is set as the chip is marked: the logo and "M1" in silver,
            // and the tier under it in that tier's colours.
            let words = name.dropFirst("Apple ".count).split(separator: " ", maxSplits: 1)
            VStack(spacing: side * 0.02) {
                HStack(alignment: .center, spacing: side * 0.01) {
                    Image(systemName: "applelogo")
                        .font(.system(size: side * 0.25, weight: .regular))
                    Text(words.first.map(String.init) ?? "")
                        .font(.system(size: side * 0.3, weight: .semibold))
                        .tracking(-side * 0.005)
                }
                .foregroundStyle(Self.silver)
                if words.count > 1 {
                    Text(words[1].uppercased())
                        .font(.system(size: side * 0.14, weight: .semibold))
                        .tracking(side * 0.01)
                        .foregroundStyle(LinearGradient(colors: Self.tierColors(String(words[1])),
                                                        startPoint: .leading, endPoint: .trailing))
                }
            }
            .offset(x: -side * 0.01)
        } else if let name {
            Text(name)
                .font(.system(size: side * 0.1, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Self.silver)
                .padding(side * 0.08)
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

/// A memory module with its capacity printed on it, filled from the left with what is
/// in use, over a row of gold contacts. Dark in both appearances, like the chip.
private struct MemoryGraphic: View {
    let capacity: String?
    let fraction: Double
    let load: Color

    var body: some View {
        let board = RoundedRectangle(cornerRadius: 4, style: .continuous)
        VStack(spacing: 2) {
            ZStack {
                board.fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)],
                                          startPoint: .top, endPoint: .bottom))
                FillFromLeading(fraction: fraction)
                    .fill(LinearGradient(colors: [load.opacity(0.6), load.opacity(0.2)],
                                         startPoint: .leading, endPoint: .trailing))
                    .clipShape(board)
                LevelEdge(fraction: fraction, axis: .horizontal).fill(load).clipShape(board)
                // The packages on the board, faint enough to be texture rather than
                // boxes the capacity sits in.
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.05))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                board.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                Text(capacity ?? MetricFormatter.unavailable)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.72)],
                                                    startPoint: .top, endPoint: .bottom))
            }
            MemoryContacts()
                .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.4),
                                              Color(red: 0.72, green: 0.55, blue: 0.22)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 5)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

/// A battery at the proportions of the system glyph, large: an outlined body and a
/// terminal, the charge inset inside it.
private struct BatteryGraphic: View {
    let fraction: Double
    let isCharging: Bool
    let charge: Color

    var body: some View {
        HStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Design.Palette.tertiaryText, lineWidth: 2.5)
                FillFromLeading(fraction: fraction)
                    .fill(charge)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(5)
                if isCharging {
                    // In the label colour with a halo of the card's, so it stands out over
                    // the charge and over the empty part alike, in either appearance.
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Design.Palette.primaryText)
                        .shadow(color: BentoCard<EmptyView>.surface, radius: 1)
                        .shadow(color: BentoCard<EmptyView>.surface, radius: 1)
                }
            }
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 0,
                                                      bottomTrailing: 3, topTrailing: 3))
                .fill(Design.Palette.tertiaryText)
                .frame(width: 4, height: 13)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

/// How full something is, as a slim capsule filled from the left in the card's
/// gradient over a pale wash of the same colour.
private struct LevelBar: View {
    let fraction: Double
    let colors: [Color]

    var body: some View {
        let capsule = Capsule(style: .continuous)
        ZStack(alignment: .leading) {
            capsule.fill(colors[0].opacity(0.18))
            FillFromLeading(fraction: fraction)
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .clipShape(capsule)
        }
        .frame(height: 7)
        .padding(.horizontal, Design.Space.xs)
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

/// A thermometer standing up: a bulb at the foot, a tube with graduations, the column
/// rising from the bulb to the reading.
private struct ThermometerGraphic: View {
    let fraction: Double
    let colors: [Color]

    var body: some View {
        let tube = Capsule(style: .continuous)
        let mercury = LinearGradient(colors: colors.reversed(), startPoint: .top, endPoint: .bottom)
        VStack(spacing: -6) {
            ZStack {
                tube.fill(colors[0].opacity(0.2))
                FillFromBottom(fraction: fraction).fill(mercury).clipShape(tube)
            }
            .frame(width: 12)
            .overlay(alignment: .trailing) {
                ThermometerScale().fill(Design.Palette.tertiaryText)
                    .frame(width: 5)
                    .padding(.vertical, 6)
                    .offset(x: 9)
            }
            Circle().fill(colors[0]).frame(width: 28, height: 28)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

// MARK: - Shape primitives

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
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 1...9 {
            let y = rect.maxY - rect.height * CGFloat(step) / 10
            let width = step == 5 ? rect.width : rect.width * 0.6
            path.addRect(CGRect(x: rect.minX, y: y - 0.5, width: width, height: 1))
        }
        return path
    }
}
