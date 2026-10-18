import SwiftUI
import AppKit
import AirStatKit

/// The MacBook style: the inside of an opened MacBook Pro seen from above, after the
/// internals wallpapers Basic Apple Guy draws, with every part showing how hard it is
/// working.
///
/// Laid out the way the machine is, loosely: the hinge and its vents along the top, a
/// blower fan in each upper corner spinning with the fan's real speed, copper heat pipes
/// running from them to the M-series chip in the middle of the logic board, its memory
/// packages beside it and the SSD's flash beside those, and the battery cells across the
/// bottom around the trackpad.
///
///     ┌────────────────── vents · Wi-Fi ──────────────────┐
///     │  ╭─────╮    ┌──── CPU ────┐            ╭─────╮   │
///     │  │ fan │════│ ▯ [ chip ] ▯│ ▯ SSD  ════│ fan │   │
///     │  ╰─────╯    └ GPU · Memory┘            ╰─────╯   │
///     │ ┌───────┐  ┌────┬────┐                ┌───────┐  │
///     │ │battery│  │ trackpad │                │battery│  │
///     │ └───────┘  └──────────┘                └───────┘  │
///     └───────────────────────────────────────────────────┘
///
/// Drawn tone on tone in one neutral, as those wallpapers are drawn in one hue, so the
/// colour on it is the data: the cores lit by their load, the memory and the flash
/// filled by how full they are, the cells by their charge. Each part carries a tag with
/// its reading and, where it has a sensor, its temperature. Pointing at a part opens its
/// detail beside the panel, as a bento card does. Built from shapes, never a `Canvas`:
/// see `PlotShape` for why.
struct MacBookView: View {
    let engine: MetricsEngine
    let settings: SettingsStore
    let layout: PanelLayoutState?

    private static let size = CGSize(width: 700, height: 460)
    private static let inset: CGFloat = 14
    static let width = size.width + inset * 2

    // Where everything sits, in the machine's own points.
    private static let vent = CGRect(x: 70, y: 12, width: 560, height: 12)
    private static let leftFins = CGRect(x: 44, y: 28, width: 152, height: 14)
    private static let rightFins = CGRect(x: 504, y: 28, width: 152, height: 14)
    private static let leftFan = CGRect(x: 34, y: 46, width: 172, height: 176)
    private static let rightFan = CGRect(x: 494, y: 46, width: 172, height: 176)
    private static let board = CGRect(x: 222, y: 36, width: 256, height: 216)
    private static let package = CGRect(x: 244, y: 60, width: 148, height: 144)
    private static let die = CGRect(x: 280, y: 67, width: 76, height: 130)
    private static let nand = CGRect(x: 404, y: 70, width: 60, height: 118)
    private static let leftCells = CGRect(x: 24, y: 268, width: 192, height: 176)
    private static let rightCells = CGRect(x: 484, y: 268, width: 192, height: 176)
    private static let middleCells = CGRect(x: 232, y: 268, width: 236, height: 26)
    private static let trackpad = CGRect(x: 232, y: 302, width: 236, height: 142)

    private var formatter: MetricFormatter {
        MetricFormatter(settings: settings.settings.general)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            chassis
            place(VentSlots().fill(Tone.part), Self.vent)
            place(VentSlots(pitch: 3).fill(Tone.fin), Self.leftFins)
            place(VentSlots(pitch: 3).fill(Tone.fin), Self.rightFins)
            fans
            place(board, Self.board)
            heatPipes
            screws
            chip
            ssd
            battery
            trackpadInfo
            tags
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .padding(Self.inset)
        .environment(\.metricFormatter, formatter)
    }

    // MARK: Case and board

    private var chassis: some View {
        let shell = RoundedRectangle(cornerRadius: 30, style: .continuous)
        let floor = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack {
            shell.fill(Tone.chassis)
            shell.strokeBorder(Tone.edge, lineWidth: 1)
            floor.fill(Tone.floor).padding(9)
            floor.strokeBorder(Tone.shadow, lineWidth: 1).padding(9)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var board: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack {
            shape.fill(Tone.board)
            BoardSpeckle().fill(Tone.speckle)
            shape.strokeBorder(Tone.edge, lineWidth: 1)
        }
    }

    /// Copper, from the fins at each fan's outlet along the top of the board and down
    /// into the chip, where the package covers their ends.
    private var heatPipes: some View {
        let copper = Color(red: 0.78, green: 0.47, blue: 0.25)
        let shine = Color(red: 0.95, green: 0.70, blue: 0.48)
        let pipes = [HeatPipe(from: CGPoint(x: 196, y: 35), along: 236, to: CGPoint(x: 268, y: 80)),
                     HeatPipe(from: CGPoint(x: 504, y: 35), along: 464, to: CGPoint(x: 368, y: 80))]
        return ZStack {
            ForEach(pipes.indices, id: \.self) { index in
                pipes[index].stroke(copper, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                pipes[index].stroke(shine.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                                            lineJoin: .round))
                    .offset(y: -2)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// What holds it all down: one at each corner of the board, and the case's own.
    private var screws: some View {
        let points = [CGPoint(x: 232, y: 46), CGPoint(x: 468, y: 46), CGPoint(x: 232, y: 242),
                      CGPoint(x: 468, y: 242), CGPoint(x: 22, y: 256), CGPoint(x: 678, y: 256),
                      CGPoint(x: 350, y: 452)]
        return ZStack {
            ForEach(points.indices, id: \.self) { index in
                ZStack {
                    Circle().fill(Tone.part)
                    Circle().strokeBorder(Tone.edge, lineWidth: 1)
                    Image(systemName: "plus").font(.system(size: 5, weight: .heavy)).foregroundStyle(Tone.fin)
                }
                .frame(width: 9, height: 9)
                .position(points[index])
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    // MARK: Fans

    private var fans: some View {
        let fans = engine.thermal.value?.fans ?? []
        return ZStack(alignment: .topLeading) {
            place(fan(fans.first).hoverRegion(.thermal, layout: layout), Self.leftFan)
            place(fan(fans.count > 1 ? fans[1] : fans.first).hoverRegion(.thermal, layout: layout),
                  Self.rightFan)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private func fan(_ fan: FanInfo?) -> some View {
        let housing = RoundedRectangle(cornerRadius: 34, style: .continuous)
        return ZStack {
            housing.fill(Tone.part)
            housing.strokeBorder(Tone.edge, lineWidth: 1)
            Circle().fill(Tone.well).frame(width: 136, height: 136).offset(y: -12)
            SpinningFan(fraction: fan?.loadFraction ?? (fan.map { min($0.currentRPM / 6000, 1) } ?? 0),
                        isSpinning: (fan?.currentRPM ?? 0) >= 1)
                .frame(width: 128, height: 128)
                .offset(y: -12)
            Text(fan.map { $0.currentRPM < 1 ? "Off" : formatter.rpm($0.currentRPM) } ?? "Fan")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Design.Palette.secondaryText)
                .offset(y: 72)
        }
    }

    // MARK: Chip

    /// The M-series package: the die, its CPU cores over its GPU cores, each lit by its
    /// load, and the memory packages either side, filled by how much is in use.
    private var chip: some View {
        let substrate = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let memory = engine.memory.value
        let usedMemory = memory.map { $0.usedFraction } ?? 0
        // Four packages for a Max's wide memory bus, two otherwise.
        let packages = (memory?.totalBytes ?? 0) >= 32 << 30 ? 4 : 2
        return ZStack(alignment: .topLeading) {
            place(ZStack {
                substrate.fill(Tone.part)
                substrate.strokeBorder(Tone.edge, lineWidth: 1)
            }, Self.package)
            place(memoryPackages(count: packages, fraction: usedMemory).hoverRegion(.memory, layout: layout),
                  Self.package.insetBy(dx: 6, dy: 6))
            place(die, Self.die)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private func memoryPackages(count: Int, fraction: Double) -> some View {
        let perSide = count / 2
        let color = palette(.memory, onCard: false)[0]
        let column = VStack(spacing: 6) {
            ForEach(0..<perSide, id: \.self) { _ in
                level(fraction, color: color, vertical: true, radius: 2, face: Tone.chipFace)
                    .frame(width: 22)
            }
        }
        return HStack(spacing: 0) {
            column
            Spacer(minLength: 0)
            column
        }
    }

    private var die: some View {
        let cpu = engine.cpu.value
        let kinds = cpu?.coreKinds ?? []
        let loads = cpu?.perCore.map(\.busy) ?? []
        let performance = loads.indices.filter { $0 >= kinds.count || kinds[$0] != .efficiency }.map { loads[$0] }
        let efficiency = loads.indices.filter { $0 < kinds.count && kinds[$0] == .efficiency }.map { loads[$0] }
        let device = engine.gpu.value?.primary
        let gpuCores = device?.coreCount ?? engine.system.value?.gpuCoreCount ?? 0
        let face = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return ZStack {
            face.fill(Tone.chipFace)
            face.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
            VStack(spacing: 5) {
                // The chip's name across its top, the way Apple prints it.
                HStack(spacing: 1.5) {
                    Image(systemName: "apple.logo").font(.system(size: 7, weight: .semibold))
                    Text(Self.chipName(engine.system.value?.chipName))
                        .font(.system(size: 7.5, weight: .semibold))
                        .tracking(0.3)
                }
                .foregroundStyle(Color(white: 0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                cpuCores(performance: performance, efficiency: efficiency)
                    .frame(height: 38)
                    .hoverRegion(.cpu, layout: layout)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                gpuGrid(cores: gpuCores, load: device?.utilization ?? 0)
                    .hoverRegion(.gpu, layout: layout)
            }
            .padding(5)
        }
    }

    /// Performance cores in two rows, efficiency cores in a narrower column beside them,
    /// each filling from the bottom with its load.
    private func cpuCores(performance: [Double], efficiency: [Double]) -> some View {
        let colors = palette(.cpu, onCard: false)
        let columns = max(1, (performance.count + 1) / 2)
        return HStack(spacing: 2) {
            VStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            core(index < performance.count ? performance[index] : nil, colors: colors)
                        }
                    }
                }
            }
            if !efficiency.isEmpty {
                VStack(spacing: 2) {
                    ForEach(efficiency.indices, id: \.self) { index in
                        core(efficiency[index], colors: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)])
                    }
                }
                .frame(width: 9)
            }
        }
    }

    @ViewBuilder
    private func core(_ load: Double?, colors: [Color]) -> some View {
        let block = RoundedRectangle(cornerRadius: 1, style: .continuous)
        if let load {
            ZStack {
                block.fill(Color.white.opacity(0.07))
                FillFromBottom(fraction: load)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .clipShape(block)
            }
        } else {
            Color.clear
        }
    }

    /// The GPU's cores eight across, switching on one by one as the load rises: macOS
    /// reports the GPU only as a whole, so the lit ones read as a level, not as which.
    private func gpuGrid(cores: Int, load: Double) -> some View {
        let columns = cores >= 8 ? 8 : max(cores, 1)
        let rows = max(1, Int((Double(cores) / Double(columns)).rounded(.up)))
        let lit = Int((min(max(load, 0), 1) * Double(cores)).rounded())
        let colors = palette(.gpu, onCard: false)
        return VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        RoundedRectangle(cornerRadius: 0.75)
                            .fill(index >= cores ? AnyShapeStyle(Color.clear)
                                  : index < lit ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading,
                                                                               endPoint: .bottomTrailing))
                                  : AnyShapeStyle(Color.white.opacity(0.07)))
                    }
                }
            }
        }
    }

    // MARK: Storage and battery

    /// The SSD's flash on the board beside the chip, filled by how full the disk is.
    private var ssd: some View {
        let root = engine.disk.value?.rootVolume
        let used = root.map { $0.totalBytes > 0 ? 1 - Double($0.availableBytes) / Double($0.totalBytes) : 0 } ?? 0
        let color = palette(.disk, onCard: false)[0]
        return place(VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { _ in
                level(used, color: color, vertical: true, radius: 3, face: Tone.chipFace)
            }
        }
        .hoverRegion(.disk, layout: layout), Self.nand)
    }

    /// Six cells around the trackpad, each filled by the pack's charge, red when low.
    private var battery: some View {
        let power = engine.power.value
        let charge = (power?.percentage ?? 0) / 100
        let isLow = power != nil && charge <= 0.2 && power?.isCharging == false
        let color = isLow ? Color(nsColor: .systemRed) : palette(.battery, onCard: false)[0]
        return ZStack(alignment: .topLeading) {
            place(cellPair(charge: charge, color: color, vertical: true)
                .hoverRegion(.battery, layout: layout), Self.leftCells)
            place(cellPair(charge: charge, color: color, vertical: true)
                .hoverRegion(.battery, layout: layout), Self.rightCells)
            place(cellPair(charge: charge, color: color, vertical: false)
                .hoverRegion(.battery, layout: layout), Self.middleCells)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private func cellPair(charge: Double, color: Color, vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(0..<2, id: \.self) { _ in
                level(charge, color: color, vertical: false, radius: 5, face: Tone.part)
                    .overlay {
                        // The cell's label, as on the real thing.
                        RoundedRectangle(cornerRadius: 2).fill(Tone.shadow)
                            .frame(width: vertical ? 54 : 30, height: vertical ? 14 : 8)
                    }
            }
        }
    }

    /// The trackpad, with what the machine is written on it.
    private var trackpadInfo: some View {
        let system = engine.system.value
        let pad = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return place(ZStack {
            pad.fill(Tone.floor)
            pad.strokeBorder(Tone.edge, lineWidth: 1)
            VStack(spacing: 4) {
                Text(system.map { $0.modelName.components(separatedBy: " (").first ?? $0.modelName } ?? "MacBook")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Design.Palette.primaryText)
                Text(system.map { "\($0.osName) \($0.osVersion)" } ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
                Text(system.map { "Up \(formatter.uptime($0.uptime))" } ?? "")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Design.Palette.tertiaryText)
            }
            .lineLimit(1)
        }
        .hoverRegion(.system, layout: layout), Self.trackpad)
    }

    // MARK: Tags

    /// Each part's reading and, where it has a sensor, its temperature, set beside it.
    private var tags: some View {
        let thermal = engine.thermal.value
        let cpu = engine.cpu.value
        let gpu = engine.gpu.value?.primary
        let memory = engine.memory.value
        let root = engine.disk.value?.rootVolume
        let power = engine.power.value
        let network = engine.network.value ?? engine.lastKnown.network.value
        return ZStack(alignment: .topLeading) {
            tag("CPU", cpu.map { formatter.percent($0.total.busy) }, colors: palette(.cpu),
                celsius: thermal?.cpuCelsius, at: CGPoint(x: 318, y: 50))
            tag("GPU", gpu?.utilization.map { formatter.percent($0) }, colors: palette(.gpu),
                celsius: thermal?.gpuCelsius, at: CGPoint(x: 318, y: 216))
            tag("Memory", memory.map { formatter.percent($0.usedFraction) }, colors: palette(.memory),
                celsius: nil, at: CGPoint(x: 290, y: 240))
            tag("SSD", root.map { formatter.storage($0.availableBytes) + " free" }, colors: palette(.disk),
                celsius: Self.hottest(thermal, .storage), at: CGPoint(x: 424, y: 240))
            tag("Battery", power?.percentage.map { formatter.percentValue($0) }, colors: palette(.battery),
                celsius: power?.temperatureCelsius ?? Self.hottest(thermal, .battery),
                at: CGPoint(x: Self.leftCells.midX, y: Self.leftCells.midY))
            tag(power.map(batteryState) ?? "Power", nil, colors: palette(.battery), celsius: nil,
                at: CGPoint(x: Self.rightCells.midX, y: Self.rightCells.midY))
            networkTag(network)
                .hoverRegion(.network, layout: layout)
                .position(x: Self.vent.midX, y: Self.vent.midY)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private func tag(_ title: String, _ value: String?, colors: [Color], celsius: Double?,
                     at point: CGPoint) -> some View {
        HStack(spacing: Design.Space.xs) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Design.Palette.secondaryText)
            if let value {
                Text(value)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .contentTransition(.numericText())
            }
            if let celsius {
                HStack(spacing: 1) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9, weight: .bold))
                    Text(formatter.temperature(celsius))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(LinearGradient(colors: [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)],
                                                startPoint: .leading, endPoint: .trailing))
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, Design.Space.s)
        .padding(.vertical, 3)
        .background(Capsule().fill(Tone.tag))
        .overlay(Capsule().strokeBorder(Tone.edge, lineWidth: 0.5))
        // The part under a tag answers the pointer, not the tag.
        .allowsHitTesting(false)
        .position(point)
    }

    private func networkTag(_ network: NetworkSnapshot?) -> some View {
        HStack(spacing: Design.Space.s) {
            Image(systemName: network?.wifi != nil || network == nil ? "wifi" : "network")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(LinearGradient(colors: palette(.network), startPoint: .leading,
                                                endPoint: .trailing))
            Text("↓ " + (network.map { formatter.networkRate($0.downloadBytesPerSecond) } ?? "—"))
                .foregroundStyle(Color(nsColor: .systemBlue))
            Text("↑ " + (network.map { formatter.networkRate($0.uploadBytesPerSecond) } ?? "—"))
                .foregroundStyle(Color(nsColor: .systemRed))
        }
        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, Design.Space.m)
        .padding(.vertical, 3)
        .background(Capsule().fill(Tone.tag))
        .overlay(Capsule().strokeBorder(Tone.edge, lineWidth: 0.5))
    }

    private func batteryState(_ power: PowerSnapshot) -> String {
        guard power.hasBattery else { return "Power adapter" }
        if power.isCharging {
            return power.timeToFull.map { "Full in \(formatter.duration($0))" } ?? "Charging"
        }
        if power.isFullyCharged { return "Charged" }
        return power.timeToEmpty.map { "\(formatter.duration($0)) left" } ?? "On battery"
    }

    // MARK: Pieces

    /// How full a part is, tone on tone: a wash of its colour up to the level, and a
    /// bright line at the level itself.
    private func level(_ fraction: Double, color: Color, vertical: Bool, radius: CGFloat,
                       face: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(face)
            Group {
                if vertical {
                    FillFromBottom(fraction: fraction).fill(color.opacity(0.4))
                    LevelLine(fraction: fraction, vertical: true).fill(color)
                } else {
                    FillFromLeading(fraction: fraction).fill(color.opacity(0.4))
                    LevelLine(fraction: fraction, vertical: false).fill(color)
                }
            }
            .clipShape(shape)
            shape.strokeBorder(Tone.edge, lineWidth: 0.75)
        }
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: fraction)
    }

    /// Sets a part at its place by layout rather than by offset, so the frame it reports
    /// for the detail beside the panel is where it is drawn.
    private func place<V: View>(_ view: V, _ rect: CGRect) -> some View {
        view.frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
    }

    private func palette(_ module: PanelModule, onCard: Bool = true) -> [Color] {
        BentoGrid.palette(module, theme: settings.settings.theme, onCard: onCard)
    }

    /// "M1 Max" out of "Apple M1 Max"; the logo beside it already says Apple.
    private static func chipName(_ name: String?) -> String {
        guard let name else { return "" }
        return name.hasPrefix("Apple ") ? String(name.dropFirst(6)) : name
    }

    private static func hottest(_ thermal: ThermalSnapshot?, _ category: SensorCategory) -> Double? {
        thermal?.sensors.filter { $0.category == category }.map(\.celsius).max()
    }

    /// One neutral in steps, light aluminium or dark graphite, for everything that is
    /// not data.
    private enum Tone {
        private static func shade(light: CGFloat, dark: CGFloat, alpha: CGFloat = 1) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                NSColor(white: appearance.isDark ? dark : light, alpha: alpha)
            })
        }

        static let chassis = shade(light: 0.80, dark: 0.16)
        static let floor = shade(light: 0.88, dark: 0.10)
        static let board = shade(light: 0.76, dark: 0.17)
        static let part = shade(light: 0.70, dark: 0.22)
        static let well = shade(light: 0.62, dark: 0.13)
        static let chipFace = shade(light: 0.16, dark: 0.08)
        static let speckle = shade(light: 0.60, dark: 0.30)
        static let fin = shade(light: 0.55, dark: 0.34)
        static let tag = shade(light: 0.97, dark: 0.20, alpha: 0.92)
        static let edge = shade(light: 1, dark: 1, alpha: 0.14)
        static let shadow = shade(light: 0, dark: 0, alpha: 0.12)
    }
}

// MARK: - Hover

extension View {
    /// Reports the pointer over a part the way a bento card does, so the part's detail
    /// opens beside the panel, and rings the part while it is open.
    func hoverRegion(_ module: PanelModule, layout: PanelLayoutState?) -> some View {
        modifier(HoverRegion(module: module, layout: layout))
    }
}

private struct HoverRegion: ViewModifier {
    let module: PanelModule
    let layout: PanelLayoutState?
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active: layout?.rowHover?(module, frame)
                case .ended: layout?.rowHover?(module, nil)
                }
            }
    }
}

// MARK: - Shapes

/// A fan's blades, curved, turning at a pace set by how fast the real fan is running:
/// a slow drift at idle, a blur at full speed, still when the fan is stopped.
private struct SpinningFan: View {
    /// 0...1, idle to flat out.
    let fraction: Double
    let isSpinning: Bool

    @State private var angle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds per turn, in steps, so a fan that wavers by a few RPM keeps its pace.
    private var period: Double {
        let step = (min(max(fraction, 0), 1) * 6).rounded() / 6
        return 2.6 - 2.1 * step
    }

    var body: some View {
        ZStack {
            FanBlades().fill(Color.white.opacity(0.22))
            FanBlades().stroke(Color.black.opacity(0.15), lineWidth: 0.5)
            Circle().fill(Color(white: 0.35)).frame(width: 34, height: 34)
            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1).frame(width: 34, height: 34)
        }
        .rotationEffect(.degrees(angle))
        .id(isSpinning && !reduceMotion ? period : 0)
        .onAppear {
            angle = 0
            guard isSpinning, !reduceMotion else { return }
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) { angle = 360 }
        }
    }
}

private struct FanBlades: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner: CGFloat = 18
        let count = 23
        for index in 0..<count {
            let a = Double(index) / Double(count) * 2 * .pi
            let sweep = 0.38
            func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
                CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
            }
            path.move(to: point(inner, a))
            path.addQuadCurve(to: point(outer, a + sweep), control: point(outer * 0.62, a + sweep * 0.15))
            path.addLine(to: point(outer, a + sweep + 0.07))
            path.addQuadCurve(to: point(inner, a + 0.1), control: point(outer * 0.6, a + sweep * 0.3))
            path.closeSubpath()
        }
        return path
    }
}

/// A heat pipe: straight along from the fins to `along`, then curving down to the chip.
private struct HeatPipe: Shape {
    let from: CGPoint
    let along: CGFloat
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: CGPoint(x: along, y: from.y))
        path.addQuadCurve(to: to, control: CGPoint(x: to.x, y: from.y))
        return path
    }
}

/// Slots side by side: the exhaust along the hinge, or a fan's fins.
private struct VentSlots: Shape {
    var pitch: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = pitch * 0.42
        var x = rect.minX + 2
        while x < rect.maxX - 2 {
            path.addRoundedRect(in: CGRect(x: x, y: rect.minY, width: width, height: rect.height),
                                cornerSize: CGSize(width: width / 2.5, height: width / 2.5))
            x += pitch
        }
        return path
    }
}

/// A bright line where a fill ends, across a part filling from the bottom, or down one
/// filling from the left.
private struct LevelLine: Shape {
    var fraction: Double
    let vertical: Bool
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let f = CGFloat(min(max(fraction, 0), 1))
        guard f > 0 else { return Path() }
        if vertical {
            return Path(CGRect(x: rect.minX, y: rect.maxY - rect.height * f, width: rect.width, height: 2))
        }
        return Path(CGRect(x: rect.minX + rect.width * f - 2, y: rect.minY, width: 2, height: rect.height))
    }
}

/// The small parts scattered over a logic board, placed by a fixed sequence so the board
/// looks the same every time it is drawn.
private struct BoardSpeckle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var seed: UInt64 = 0x2545F491
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        for _ in 0..<170 {
            let wide = next() > 0.5
            let size = wide ? CGSize(width: 5, height: 2.5) : CGSize(width: 2.5, height: 4)
            path.addRect(CGRect(x: rect.minX + 6 + next() * (rect.width - 16),
                                y: rect.minY + 6 + next() * (rect.height - 16),
                                width: size.width, height: size.height))
        }
        return path
    }
}

/// The bottom `fraction` of a rect.
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
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * min(max(fraction, 0), 1),
                    height: rect.height))
    }
}
