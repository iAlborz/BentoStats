import SwiftUI
import AppKit
import AirStatKit

/// The bento style: every module as a card in a grid of mixed sizes, the way Apple lays
/// out what is new in a Mac.
///
/// One fixed composition rather than a flowing grid. A bento grid works when the big
/// cards are the ones that matter most and the small ones fill in around them, which is
/// a design decision, not something a layout algorithm makes. Six columns by three rows
/// puts the whole panel at 3:2, landscape, with the panel's two actions as two
/// half-height cards in the last column in place of a footer:
///
///     ┌─────────┬─────────┬────┬────┐
///     │         │ Memory  │Batt│    │
///     │   CPU   ├─────────┼────┤Temp│
///     │         │   GPU   │Proc│    │
///     ├─────────┼─────────┼────┼────┤
///     │ Network │   SSD   │Up- │ ⚙︎ │
///     │         │         │time├────┤
///     │         │         │    │ ⏻  │
///     └─────────┴─────────┴────┴────┘
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

    private static let inset: CGFloat = 12
    private static let gap: CGFloat = 10
    /// One of six columns and one of three rows. A little taller than wide, which is
    /// what brings six by three out at 3:2 overall: 644 by 428.
    private static let unitWidth: CGFloat = 95
    private static let unitHeight: CGFloat = 128
    private static let wide = unitWidth * 2 + gap
    private static let tall = unitHeight * 2 + gap
    static let width = inset * 2 + unitWidth * 6 + gap * 5

    @Environment(\.panelActions) private var actions

    private var formatter: MetricFormatter {
        MetricFormatter(settings: settings.settings.general)
    }

    var body: some View {
        VStack(spacing: Self.gap) {
            HStack(alignment: .top, spacing: Self.gap) {
                cpu
                VStack(spacing: Self.gap) { memory; gpu }
                VStack(spacing: Self.gap) { battery; processes }
                thermal
            }
            HStack(spacing: Self.gap) {
                network
                disk
                system
                VStack(spacing: Self.gap) {
                    action("Settings", symbol: "gearshape.fill",
                           colors: [Color(nsColor: .systemGray), Color(nsColor: .secondaryLabelColor)],
                           perform: actions.openSettings)
                        .keyboardShortcut(",", modifiers: .command)
                    action("Quit", symbol: "power",
                           colors: [Color(nsColor: .systemRed), Color(nsColor: .systemPink)],
                           perform: actions.quit)
                        .keyboardShortcut("q", modifiers: .command)
                }
            }
        }
        .padding(Self.inset)
        .environment(\.metricFormatter, formatter)
    }

    // MARK: Cards

    private var cpu: some View {
        let cpu = engine.cpu.value
        let busy = cpu?.total.busy
        let system = engine.system.value
        // Each core's own load beside its kind. A core the system did not classify is
        // drawn as a performance core: that is what a chip without the split has.
        let cores = cpu.map { cpu in
            cpu.perCore.indices.map { index in
                (kind: index < cpu.coreKinds.count ? cpu.coreKinds[index] : .unknown,
                 busy: cpu.perCore[index].busy)
            }
        } ?? []
        let caption = system.map { system in
            system.efficiencyCores > 0
                ? "\(system.physicalCores)-core CPU · \(system.performanceCores)P + \(system.efficiencyCores)E"
                : "\(system.physicalCores)-core CPU"
        }
        return card(.cpu, width: Self.wide, height: Self.tall, caption: caption ?? "CPU") {
            VStack(spacing: Design.Space.m) {
                ChipGraphic(name: system?.chipName,
                            performance: cores.filter { $0.kind != .efficiency }.map(\.busy),
                            efficiency: cores.filter { $0.kind == .efficiency }.map(\.busy),
                            performanceColors: palette(.cpu, onCard: false),
                            efficiencyColors: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)])
                    .frame(width: 150, height: 150)
                bigNumber(.cpu, busy.map { formatter.percent($0) }, size: 28)
            }
        }
    }

    private var memory: some View {
        let memory = engine.memory.value
        let used = memory.map { $0.totalBytes > 0 ? Double($0.usedBytes) / Double($0.totalBytes) : 0 }
        return card(.memory, width: Self.wide, height: Self.unitHeight,
                    caption: memory.map { "Memory · \(formatter.memory($0.usedBytes)) used" } ?? "Memory") {
            MemoryGraphic(capacity: memory.map { Self.marketingCapacity($0.totalBytes) },
                          fraction: used ?? 0, load: palette(.memory, onCard: false)[0])
                .frame(width: 180, height: 56)
        }
    }

    private var gpu: some View {
        let device = engine.gpu.value?.primary
        let cores = device?.coreCount ?? engine.system.value?.gpuCoreCount
        let load = device?.utilization
        return card(.gpu, width: Self.wide, height: Self.unitHeight,
                    caption: cores.map { "\($0)-core GPU" } ?? "GPU") {
            HStack(spacing: Design.Space.l) {
                if let cores, cores > 0 {
                    GPUDie(cores: cores, load: load ?? 0, colors: palette(.gpu, onCard: false), cell: 8.5)
                } else {
                    bigNumber(.gpu, nil, size: 24)
                }
                // The three figures the driver publishes. macOS reports the GPU only as
                // a whole, never core by core, so a meter per core would be invented.
                GPUMeters(channels: [("Device", load), ("Renderer", device?.rendererUtilization),
                                     ("Tiler", device?.tilerUtilization)]
                              .compactMap { name, value in value.map { (name, $0) } },
                          colors: palette(.gpu), formatter: formatter)
            }
        }
    }

    private var disk: some View {
        let disk = engine.disk.value
        let root = disk?.rootVolume
        // The number and its unit are set apart, as Apple sets "1TB", so the number can
        // be large without the unit crowding it.
        let parts = root.map { formatter.storage($0.availableBytes).split(separator: " ") }
        return card(.disk, width: Self.wide, height: Self.unitHeight,
                    caption: root.map { "\(formatter.storage($0.totalBytes)) SSD" } ?? "SSD") {
            VStack(spacing: Design.Space.s) {
                // How full the disk is, from the same available space as the number under
                // it so the two agree, the way Finder and System Settings count it.
                SSDGraphic(fraction: root.map { $0.totalBytes > 0
                               ? 1 - Double($0.availableBytes) / Double($0.totalBytes) : 0 } ?? 0,
                           colors: palette(.disk, onCard: false))
                    .frame(width: 176, height: 44)
                HStack(alignment: .center) {
                    numberWithUnit(.disk, parts?.first.map(String.init),
                                   unit: (parts.flatMap { $0.count > 1 ? String($0[1]) : nil } ?? "") + " free",
                                   size: 24)
                    Spacer(minLength: Design.Space.s)
                    VStack(alignment: .trailing, spacing: 1) {
                        diskRate("Read", disk?.readBytesPerSecond)
                        diskRate("Write", disk?.writeBytesPerSecond)
                    }
                }
                .padding(.horizontal, Design.Space.xs)
            }
        }
    }

    private var battery: some View {
        let power = engine.power.value
        return card(.battery, width: Self.unitWidth, height: Self.unitHeight,
                    caption: power.map(batteryCaption) ?? "Battery") {
            VStack(spacing: Design.Space.s) {
                if let power, !power.hasBattery {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(gradient(.battery))
                    bigNumber(.battery, "AC", size: 22)
                } else {
                    let fraction = (power?.percentage ?? 0) / 100
                    let isLow = power != nil && fraction <= 0.2 && power?.isCharging == false
                    BatteryGraphic(fraction: fraction, isCharging: power?.isCharging ?? false,
                                   charge: isLow ? Color(nsColor: .systemRed) : palette(.battery)[0],
                                   scale: 0.7)
                        .frame(width: 62, height: 28)
                    bigNumber(.battery, power?.percentage.map { formatter.percentValue($0) }, size: 24,
                              colors: isLow ? [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)] : nil)
                }
            }
        }
    }

    private var network: some View {
        let network = engine.network.value
        return card(.network, width: Self.wide, height: Self.unitHeight,
                    caption: network.map { $0.wifi?.ssid ?? $0.connectionType.label } ?? "Network") {
            HStack(spacing: Design.Space.l) {
                // Wi-Fi when that is the connection, the generic network glyph otherwise.
                Image(systemName: network?.wifi != nil || network == nil ? "wifi" : "network")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(gradient(.network))
                // Upload over download, in Activity Monitor's colours for the two
                // directions: red going out, blue coming in.
                VStack(alignment: .leading, spacing: 0) {
                    rate("arrow.up", network.map { formatter.networkRate($0.uploadBytesPerSecond) },
                         colors: [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)])
                    rate("arrow.down", network.map { formatter.networkRate($0.downloadBytesPerSecond) },
                         colors: [Color(nsColor: .systemBlue), Color(nsColor: .systemCyan)])
                }
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
                    .frame(width: 30, height: 150)
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

    /// One of the panel's two actions as a half-height card of its own: a symbol in its
    /// gradient beside its name, the whole card the button. Half height, because they
    /// are furniture and should not weigh as much as a reading.
    private func action(_ title: String, symbol: String, colors: [Color],
                        perform: @escaping @MainActor () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: Design.Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(gradient(colors))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
            }
            .frame(width: Self.unitWidth, height: (Self.unitHeight - Self.gap) / 2)
        }
        .buttonStyle(BentoActionStyle())
        .accessibilityLabel(title)
    }

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
        if let custom = settings.settings.theme.color(for: module.requiredSource) {
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

/// A card that is a button: the card's own surface, a step darker under the pointer and
/// another while pressed, the way a system button answers.
private struct BentoActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BentoActionBody(configuration: configuration)
    }
}

private struct BentoActionBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .background(shape.fill(BentoCard<EmptyView>.surface))
            .overlay(shape.fill(Design.Palette.primaryText
                .opacity(configuration.isPressed ? 0.12 : isHovering ? 0.06 : 0)))
            .contentShape(shape)
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
            let face = Rectangle()
            ZStack {
                face.fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.07)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                // The sheen: a soft diagonal lift across the top-left of the die.
                face.fill(LinearGradient(colors: [.white.opacity(0.07), .clear],
                                         startPoint: .topLeading, endPoint: .center))
                face.strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.04),
                                                          .white.opacity(0.14)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1)
                if performance.isEmpty && efficiency.isEmpty {
                    // No cores read yet: the name alone, at the size it has on its own.
                    lettering(side: side, scale: 1)
                } else {
                    VStack(spacing: side * 0.07) {
                        lettering(side: side, scale: 0.62)
                        ChipCores(performance: performance, efficiency: efficiency,
                                  width: side * 0.84,
                                  performanceColors: performanceColors,
                                  efficiencyColors: efficiencyColors)
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static let silver = LinearGradient(colors: [Color(white: 0.97), Color(white: 0.66)],
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
    let width: CGFloat
    let performanceColors: [Color]
    let efficiencyColors: [Color]

    private static let gap: CGFloat = 1.75
    private static let clusterGap: CGFloat = 3.5
    private static let efficiencyWidth: CGFloat = 0.55

    var body: some View {
        let pColumns = Self.columns(performance.count)
        let eColumns = Self.columns(efficiency.count)
        let units = CGFloat(pColumns) + CGFloat(eColumns) * Self.efficiencyWidth
        let gaps = CGFloat(max(pColumns - 1, 0) + max(eColumns - 1, 0)) * Self.gap
            + (pColumns > 0 && eColumns > 0 ? Self.clusterGap : 0)
        let side = min((width - gaps) / max(units, 1), 28)
        HStack(alignment: .top, spacing: Self.clusterGap) {
            if pColumns > 0 {
                cluster(performance, columns: pColumns,
                        size: CGSize(width: side, height: side), colors: performanceColors)
            }
            if eColumns > 0 {
                cluster(efficiency, columns: eColumns,
                        size: CGSize(width: side * Self.efficiencyWidth, height: side),
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
private struct GPUMeters: View {
    let channels: [(name: String, value: Double)]
    let colors: [Color]
    let formatter: MetricFormatter

    var body: some View {
        VStack(spacing: Design.Space.s) {
            ForEach(Array(channels.enumerated()), id: \.offset) { _, channel in
                VStack(spacing: 3) {
                    HStack {
                        Text(channel.name)
                        Spacer(minLength: Design.Space.xs)
                        Text(formatter.percent(channel.value)).monospacedDigit()
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

    private static let count = 24

    var body: some View {
        let lit = Int((min(max(fraction, 0), 1) * Double(Self.count)).rounded())
        ZStack {
            Ticks(count: Self.count, range: lit..<Self.count).fill(colors[0].opacity(0.18))
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .mask(Ticks(count: Self.count, range: 0..<lit))
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: lit)
    }
}

/// `count` equal vertical ticks across the rect with gaps between them, keeping those
/// whose index falls in `range`.
private struct Ticks: Shape {
    let count: Int
    let range: Range<Int>

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let gap: CGFloat = 1.5
        let width = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
        for index in range {
            let x = rect.minX + CGFloat(index) * (width + gap)
            path.addRoundedRect(in: CGRect(x: x, y: rect.minY, width: width, height: rect.height),
                                cornerSize: CGSize(width: width / 2, height: width / 2))
        }
        return path
    }
}

/// The GPU drawn as its cores: a dark die with one cell per core, eight across, so a
/// 32-core GPU reads as the 4 by 8 block it is.
///
/// Cells switch on one by one as the load rises, in reading order: at 18% of 32 cores,
/// the first six. macOS reports the GPU only as a whole, so the cells are lit in order,
/// which reads as a level, rather than scattered, which would claim to know which cores
/// are busy.
private struct GPUDie: View {
    let cores: Int
    let load: Double
    let colors: [Color]
    var cell: CGFloat = 6.5

    private static let gap: CGFloat = 2
    private static let padding: CGFloat = 4

    var body: some View {
        let columns = cores % 8 == 0 || cores > 8 ? min(cores, 8) : cores
        let rows = Int((Double(cores) / Double(columns)).rounded(.up))
        let size = CGSize(width: cell * CGFloat(columns) + Self.gap * CGFloat(columns - 1),
                          height: cell * CGFloat(rows) + Self.gap * CGFloat(rows - 1))
        let lit = Int((min(max(load, 0), 1) * Double(cores)).rounded())
        let die = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack {
            die.fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.07)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
            die.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            ZStack {
                CoreCells(columns: columns, cells: lit..<cores, cell: cell, gap: Self.gap)
                    .fill(Color.white.opacity(0.1))
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .mask(CoreCells(columns: columns, cells: 0..<lit, cell: cell, gap: Self.gap))
                    .shadow(color: colors[0].opacity(0.7), radius: 2.5)
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width + Self.padding * 2, height: size.height + Self.padding * 2)
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: lit)
    }
}

/// Rounded cells of a core grid laid out row by row: the cores in `cells`.
private struct CoreCells: Shape {
    let columns: Int
    let cells: Range<Int>
    let cell: CGFloat
    let gap: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in cells {
            let x = rect.minX + CGFloat(index % columns) * (cell + gap)
            let y = rect.minY + CGFloat(index / columns) * (cell + gap)
            path.addRoundedRect(in: CGRect(x: x, y: y, width: cell, height: cell),
                                cornerSize: CGSize(width: cell * 0.25, height: cell * 0.25),
                                style: .continuous)
        }
        return path
    }
}

/// A memory module with its capacity printed on it, filled from the left with what is
/// in use, over a row of gold contacts. Dark in both appearances, like the chip.
private struct MemoryGraphic: View {
    let capacity: String?
    let fraction: Double
    let load: Color

    /// The board under the contacts: the module's dark finish a shade lighter, so the
    /// strip stands off a dark card as well as a white one.
    static let backing = LinearGradient(colors: [Color(white: 0.24), Color(white: 0.14)],
                                        startPoint: .top, endPoint: .bottom)
    /// The strip's edge. The boards are told apart from a dark card by their hairline;
    /// the strip needs one too, a little brighter for being so much smaller.
    static let backingEdge = Color.white.opacity(0.2)

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
                // The memory packages, eight across as on a module.
                HStack(spacing: 4) {
                    ForEach(0..<8, id: \.self) { _ in BoardPackage() }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                board.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                Text(capacity ?? MetricFormatter.unavailable)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.72)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.55), radius: 2)
            }
            ZStack {
                EdgeBacking(axis: .horizontal, notchFraction: 0.42, notchOffset: -4, notchLength: 8)
                    .fill(Self.backing)
                EdgeBacking(axis: .horizontal, notchFraction: 0.42, notchOffset: -4, notchLength: 8)
                    .stroke(Self.backingEdge, lineWidth: 0.75)
                MemoryContacts()
                    .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.4),
                                                  Color(red: 0.72, green: 0.55, blue: 0.22)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(.vertical, 1.5)
            }
            .frame(height: 8)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
}

/// An M.2 SSD: the edge connector's gold pins on the left, broken by the key notch, then
/// a long dark board carrying the controller and three flash packages, with the
/// half-round cut for its screw at the far end.
///
/// The board is the meter, as the memory module is: it fills from the left with how
/// full the disk is, and the controller and flash packages sit on top of the fill, so it
/// still reads as a drive. The connector stands apart from it, as the memory module's
/// contacts do, and stays gold whatever the level.
private struct SSDGraphic: View {
    let fraction: Double
    let colors: [Color]

    var body: some View {
        let board = RoundedRectangle(cornerRadius: 3, style: .continuous)
        HStack(spacing: 2) {
            ZStack {
                EdgeBacking(axis: .vertical, notchFraction: 0.3, notchOffset: -1, notchLength: 6)
                    .fill(MemoryGraphic.backing)
                EdgeBacking(axis: .vertical, notchFraction: 0.3, notchOffset: -1, notchLength: 6)
                    .stroke(MemoryGraphic.backingEdge, lineWidth: 0.75)
                SSDPins()
                    .fill(LinearGradient(colors: [Color(red: 0.72, green: 0.55, blue: 0.22),
                                                  Color(red: 0.93, green: 0.78, blue: 0.4)],
                                         startPoint: .leading, endPoint: .trailing))
                    .padding(.horizontal, 1.5)
            }
            .frame(width: 9)
            ZStack {
            board.fill(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.09)],
                                      startPoint: .top, endPoint: .bottom))
            FillFromLeading(fraction: fraction)
                .fill(LinearGradient(colors: [colors[0].opacity(0.65), colors[colors.count - 1].opacity(0.25)],
                                     startPoint: .leading, endPoint: .trailing))
                .clipShape(board)
            LevelEdge(fraction: fraction, axis: .horizontal).fill(colors[0]).clipShape(board)
            board.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            HStack(spacing: 5) {
                BoardPackage().frame(width: 22, height: 22)
                ForEach(0..<3, id: \.self) { _ in
                    BoardPackage().frame(height: 30)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            // The screw's half-round cut, in the card's own colour so it reads as a
            // notch out of the board.
            HStack {
                Spacer()
                Circle().fill(BentoCard<EmptyView>.surface).frame(width: 10, height: 10)
                    .offset(x: 5)
            }
            }
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }
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

/// The strip of board an edge connector's fingers sit on, cut through by the key notch:
/// along the bottom of a module (`.horizontal`) or down the end of a drive
/// (`.vertical`). The notch starts at `notchFraction` of the strip's length, moved by
/// `notchOffset` points, so it lines up with the gap the fingers leave.
private struct EdgeBacking: Shape {
    let axis: Axis
    let notchFraction: CGFloat
    let notchOffset: CGFloat
    let notchLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = CGSize(width: 1.5, height: 1.5)
        switch axis {
        case .horizontal:
            let start = rect.minX + rect.width * notchFraction + notchOffset
            path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY,
                                           width: start - rect.minX, height: rect.height),
                                cornerSize: radius)
            path.addRoundedRect(in: CGRect(x: start + notchLength, y: rect.minY,
                                           width: rect.maxX - start - notchLength, height: rect.height),
                                cornerSize: radius)
        case .vertical:
            let start = rect.minY + rect.height * notchFraction + notchOffset
            path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY,
                                           width: rect.width, height: start - rect.minY),
                                cornerSize: radius)
            path.addRoundedRect(in: CGRect(x: rect.minX, y: start + notchLength,
                                           width: rect.width, height: rect.maxY - start - notchLength),
                                cornerSize: radius)
        }
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
private struct BatteryGraphic: View {
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
