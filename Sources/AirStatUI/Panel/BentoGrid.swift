import SwiftUI
import AppKit
import AirStatKit

/// The bento style: every module as a card in a grid of mixed sizes, the way Apple lays
/// out what is new in a Mac.
///
/// One fixed composition rather than a flowing grid. A bento grid works when the big
/// cards are the ones that matter most and the small ones fill in around them, which is
/// a design decision, not something a layout algorithm makes. The grid is square cells,
/// six across and four down, which puts the panel at 3:2, landscape, and every card
/// spans a whole number of them — 1×1, 2×1, 1×2, 2×2 or 2×3 — so no card is a size of
/// its own. The panel's two actions take a cell each:
///
///     ┌─────────┬─────────┬─────────┐
///     │         │         │   SSD   │
///     │   CPU   │   GPU   ├─────────┤
///     │         │         │ Battery │
///     │         ├─────────┼────┬────┤
///     │         │ Memory  │    │ ⚙︎  │
///     ├─────────┼────┬────┤Temp├────┤
///     │ Network │Proc│ Up │    │ ⏻  │
///     └─────────┴────┴────┴────┴────┘
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
    /// One square cell. Six by four of them, with the gaps and the inset, is 734 by 494.
    private static let cell: CGFloat = 110
    static let width = inset * 2 + span(6)

    /// The length of `cells` cells and the gaps between them, across or down.
    private static func span(_ cells: Int) -> CGFloat {
        cell * CGFloat(cells) + gap * CGFloat(cells - 1)
    }

    @Environment(\.panelActions) private var actions

    private var formatter: MetricFormatter {
        MetricFormatter(settings: settings.settings.general)
    }

    var body: some View {
        // Three column pairs, each stacked top to bottom.
        HStack(alignment: .top, spacing: Self.gap) {
            VStack(spacing: Self.gap) { cpu; network }
            VStack(spacing: Self.gap) {
                gpu
                memory
                HStack(spacing: Self.gap) { processes; system }
            }
            VStack(spacing: Self.gap) {
                disk
                battery
                HStack(alignment: .top, spacing: Self.gap) {
                    thermal
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
        let efficiencyColors = [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)]
        return card(.cpu, width: Self.span(2), height: Self.span(3), caption: caption ?? "CPU") {
            VStack(spacing: Design.Space.l) {
                ChipGraphic(name: system?.chipName,
                            performance: cores.filter { $0.kind != .efficiency }.map(\.busy),
                            efficiency: cores.filter { $0.kind == .efficiency }.map(\.busy),
                            performanceColors: palette(.cpu, onCard: false),
                            efficiencyColors: efficiencyColors)
                    .frame(width: 200, height: 200)
                bigNumber(.cpu, busy.map { formatter.percent($0) }, size: 32)
                // The two kinds of core, each in the colour its blocks fill with.
                if let performance = cpu?.performanceBusy, let efficiency = cpu?.efficiencyBusy {
                    HStack(spacing: Design.Space.l) {
                        coreShare("Performance", performance, color: palette(.cpu)[0])
                        coreShare("Efficiency", efficiency, color: efficiencyColors[0])
                    }
                }
            }
        }
    }

    private var memory: some View {
        let memory = engine.memory.value
        let used = memory.map { $0.totalBytes > 0 ? Double($0.usedBytes) / Double($0.totalBytes) : 0 }
        // Free is what the fill leaves: everything not counted as used, the way the SSD
        // reports its available space.
        let free = memory.map { $0.totalBytes > $0.usedBytes ? $0.totalBytes - $0.usedBytes : 0 }
        return card(.memory, width: Self.span(2), height: Self.span(1),
                    caption: memory.map { "\(Self.marketingCapacity($0.totalBytes)) Memory" } ?? "Memory") {
            MemoryGraphic(label: free.map { "\(formatter.memory($0)) free" },
                          fraction: used ?? 0, load: palette(.memory, onCard: false)[0])
                .frame(width: 200, height: 56)
        }
    }

    private var gpu: some View {
        let device = engine.gpu.value?.primary
        let cores = device?.coreCount ?? engine.system.value?.gpuCoreCount
        let load = device?.utilization
        // What the GPU holds of the shared memory, against the most macOS will let it
        // have: not memory of its own, a share of the one pool the Memory card shows.
        var memory: GPUChannel?
        if let used = device?.vramUsedBytes, let total = device?.vramTotalBytes, total > 0 {
            memory = GPUChannel(name: "Memory", value: Double(used) / Double(total),
                                detail: "\(formatter.memory(used)) of \(formatter.memory(total))")
        }
        let caption = cores.map { cores in
            "\(cores)-core GPU" + (load.map { " · \(formatter.percent($0))" } ?? "")
        }
        return card(.gpu, width: Self.span(2), height: Self.span(2), caption: caption ?? "GPU") {
            VStack(spacing: Design.Space.m) {
                if let cores, cores > 0 {
                    GPUDie(cores: cores, load: load ?? 0, colors: palette(.gpu, onCard: false),
                           size: CGSize(width: 196, height: 106))
                } else {
                    bigNumber(.gpu, nil, size: 24)
                }
                // The die already draws the overall load, so the meters carry what it
                // cannot: the GPU's memory, then the renderer and tiler the driver reports.
                // macOS reports the GPU only as a whole, never core by core.
                GPUMeters(channels: [memory,
                                     device?.rendererUtilization.map { GPUChannel(name: "Renderer", value: $0) },
                                     device?.tilerUtilization.map { GPUChannel(name: "Tiler", value: $0) }]
                              .compactMap { $0 },
                          colors: palette(.gpu), formatter: formatter)
                    .padding(.horizontal, Design.Space.xs)
            }
        }
    }

    private var disk: some View {
        let disk = engine.disk.value
        let root = disk?.rootVolume
        return card(.disk, width: Self.span(2), height: Self.span(1),
                    caption: root.map { "\(formatter.storage($0.totalBytes)) SSD" } ?? "SSD") {
            VStack(spacing: Design.Space.s) {
                // How full the disk is, from the same available space as the label printed
                // on it so the two agree, the way Finder and System Settings count it.
                SSDGraphic(fraction: root.map { $0.totalBytes > 0
                               ? 1 - Double($0.availableBytes) / Double($0.totalBytes) : 0 } ?? 0,
                           colors: palette(.disk, onCard: false),
                           label: root.map { "\(formatter.storage($0.availableBytes)) free" })
                    .frame(width: 200, height: 44)
                HStack(spacing: Design.Space.xl) {
                    diskRate("Read", disk?.readBytesPerSecond)
                    diskRate("Write", disk?.writeBytesPerSecond)
                }
            }
        }
    }

    private var battery: some View {
        let power = engine.power.value
        return card(.battery, width: Self.span(2), height: Self.span(1),
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
        return card(.network, width: Self.span(2), height: Self.span(1),
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
        return card(.thermal, width: Self.span(1), height: Self.span(2),
                    caption: caption ?? "Temperature") {
            VStack(spacing: Design.Space.m) {
                // Red whatever the metric's colour: on a thermometer red is the reading,
                // and the top of the scale is where it means danger.
                ThermometerGraphic(fraction: celsius.map { min(max(($0 - 30) / 70, 0), 1) } ?? 0,
                                   colors: [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)])
                    .frame(width: 30, height: 140)
                bigNumber(.thermal, celsius.map { formatter.temperature($0) } ?? thermal?.pressure.label,
                          size: celsius == nil ? 17 : 26)
            }
        }
    }

    private var processes: some View {
        let processes = engine.processes.value
        let top = processes.map { Array($0.processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5)) } ?? []
        return card(.processes, width: Self.span(1), height: Self.span(1), caption: "processes",
                    footer: top.isEmpty ? nil : AnyView(ProcessIconRow(processes: top))) {
            VStack(spacing: 0) {
                bigNumber(.processes, processes.map { formatter.count($0.totalProcessCount) }, size: 28)
                // The caption is the icon row, so the count is labelled here.
                if !top.isEmpty {
                    Text("processes")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Design.Palette.secondaryText)
                }
            }
        }
    }

    private var system: some View {
        let system = engine.system.value
        return card(.system, width: Self.span(1), height: Self.span(1), caption: "uptime") {
            bigNumber(.system, system.map { formatter.uptime($0.uptime) }, size: 22)
        }
    }

    // MARK: Pieces

    /// One of the panel's two actions as a card of its own, one cell: a symbol in its
    /// gradient over its name, the whole card the button.
    private func action(_ title: String, symbol: String, colors: [Color],
                        perform: @escaping @MainActor () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button(action: perform) {
            VStack(spacing: Design.Space.s) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(gradient(colors))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
            }
            .frame(width: Self.cell, height: Self.cell)
        }
        .buttonStyle(BentoActionStyle())
        .background(shape.fill(BentoCard<EmptyView>.surface))
        .clipShape(shape)
        .accessibilityLabel(title)
    }

    /// One kind of core's share of the load: a dot in its colour, its name, its figure.
    private func coreShare(_ name: String, _ busy: Double, color: Color) -> some View {
        HStack(spacing: Design.Space.xs) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Design.Palette.secondaryText)
            Text(formatter.percent(busy))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Design.Palette.primaryText)
        }
    }

    private func card<Content: View>(_ module: PanelModule, width: CGFloat, height: CGFloat,
                                     caption: String, footer: AnyView? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        BentoCard(module: module, caption: caption, footer: footer, ring: palette(module)[0],
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
    /// Drawn in the caption's place when a card has something better to say there.
    let footer: AnyView?
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
            if let footer {
                footer
            } else {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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
        VStack(spacing: 5) {
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
/// between them, so a 32-core GPU reads as four blocks of eight. The channel across the
/// middle carries the chip's name, the Apple logo and "GPU" in the CPU chip's silver.
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
    private static let inset: CGFloat = 6
    private static let gap: CGFloat = 3
    /// Between the clusters.
    private static let channel: CGFloat = 8
    /// The channel across the middle, which carries the label.
    private static let band: CGFloat = 20

    var body: some View {
        let columns = cores % 8 == 0 || cores > 8 ? min(cores, 8) : cores
        let rows = Int((Double(cores) / Double(columns)).rounded(.up))
        // Split down the middle each way where the grid divides evenly.
        let columnSplit = columns >= 4 && columns % 2 == 0 ? columns / 2 : nil
        let rowSplit = rows >= 2 && rows % 2 == 0 ? rows / 2 : nil
        let package = CGSize(width: size.width - Self.leg * 2, height: size.height - Self.leg * 2)
        let across = Self.gap * CGFloat(columns - 1) + (columnSplit == nil ? 0 : Self.channel - Self.gap)
        let down = Self.gap * CGFloat(rows - 1) + (rowSplit == nil ? 0 : Self.band - Self.gap)
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
                        if row == rowSplit {
                            label.frame(height: Self.band)
                        } else {
                            Color.clear.frame(height: Self.gap)
                        }
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
        }
        .frame(width: size.width, height: size.height)
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: lit)
    }

    /// The logo and "GPU", set as the CPU chip's "M1" is.
    private var label: some View {
        HStack(alignment: .center, spacing: 2) {
            Image(systemName: "applelogo")
                .font(.system(size: 12, weight: .regular))
            Text("GPU")
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.5)
        }
        .foregroundStyle(ChipGraphic.silver)
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
/// the card's colour while lit. Square-cornered, as the CPU's cores are.
private struct GPUBlock: View {
    let isLit: Bool
    let colors: [Color]

    var body: some View {
        let block = RoundedRectangle(cornerRadius: 1, style: .continuous)
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
                ZStack {
                    ThermometerScale(danger: false).fill(Design.Palette.tertiaryText)
                    ThermometerScale(danger: true).fill(Color(nsColor: .systemRed))
                }
                .frame(width: 6)
                .padding(.vertical, 6)
                .offset(x: 10)
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
        for degrees in stride(from: Self.lowest + Self.step, through: Self.highest, by: Self.step)
        where (degrees >= Self.dangerFrom) == danger {
            let y = rect.maxY - rect.height * CGFloat(degrees - Self.lowest) / span
            // Every ten degrees runs the full width; the marks between are shorter.
            let width = degrees % 10 == 0 ? rect.width : rect.width * 0.55
            path.addRect(CGRect(x: rect.minX, y: y - 0.5, width: width, height: 1))
        }
        return path
    }
}

/// The top processes' icons in a row: the app's own icon, or a gear for a process
/// with no app around it.
private struct ProcessIconRow: View {
    let processes: [ProcessRow]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(processes, id: \.pid) { process in
                switch PanelAppIcon.icon(for: process) {
                case .bundle(let image):
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 14, height: 14)
                case .executable:
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Design.Palette.secondaryText)
                        .frame(width: 14, height: 14)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Top processes: " + processes.map(\.name).joined(separator: ", "))
    }
}
