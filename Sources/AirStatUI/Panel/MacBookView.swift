import SwiftUI
import AppKit
import AirStatKit

/// The MacBook style: the inside of a MacBook Pro seen from above with its bottom case
/// off, after the internals wallpapers Basic Apple Guy draws, built from the bento's own
/// parts: the CPU chip, the GPU, the memory module and the SSD its cards draw, laid out
/// on one logic board, each showing how hard it is working.
///
/// Laid out the way the machine is, but spaced out so each part has room for its
/// reading: the hinge and its vents along the top; a blower fan in each upper corner,
/// spinning with the fan's real speed and blowing through copper fins into the hinge;
/// the logic board up between the fans and right across under them, its edge running
/// round their housings, with heat pipes from the fins along the tops of the CPU and
/// the GPU, a thermometer on the outer side of each, under the fans the memory in its
/// slot, the Wi-Fi module and the SSD in its socket, and traces running between them
/// all; then the battery's cells either side of the trackpad, a speaker at each edge,
/// and the ports along the sides.
///
///     ┌── hinge ─────────────────── vents ──────────────────── hinge ──┐
///     │ ┌ fins ┐ ╭────────────── logic board ───────────────╮ ┌ fins ┐ │
///     │ │ fan  │ │   ┃  ┌─ CPU ─┐  ┌────── GPU ──────┐  ┃   │ │ fan  │ │
///     │ │ 27%  │ │   ┃  │  34%  │  │       18%       │  ┃   │ │ 26%  │ │
///     │ ╰──────╯ │   ●  └───────┘  └─────────────────┘  ●   │ ╰──────╯ │
///     │ ╭────────╯   52°                              43°   ╰────────╮ │
///     │ │   memory: 7.7 GB free     Wi-Fi ↑ ↓     SSD: 185 GB free   │ │
///     │ ╰────────────────────────────────────────────────────────────╯ │
///     │ ┌─┐ ┌ cells ┐ ┌─────────── trackpad ───────────┐ ┌ cells ┐ ┌─┐ │
///     │ └─┘ └───────┘ └────────────────────────────────┘ └───────┘ └─┘ │
///     └────────────────────────────────────────────────────────────────┘
///
/// The case is drawn tone on tone in one neutral, as those wallpapers are drawn in one
/// hue, and the bento's parts keep their own dark finish, so the colour on it is the
/// data: the cores lit by their load, the memory and the drive filled by how full they
/// are, the cells by their charge. Every reading sits on its part, as the bento prints
/// what is free on the memory and the drive: a fan's speed on its hub, a chip's load
/// under its name, the network's rates on the Wi-Fi module's label. A chip's
/// temperature stands on a thermometer beside it, and the memory and the SSD are named
/// under them. Pointing at a part opens its detail beside the panel, as a bento card does.
/// Built from shapes, never a `Canvas`: see `PlotShape` for why.
struct MacBookView: View {
    let engine: MetricsEngine
    let settings: SettingsStore
    let layout: PanelLayoutState?

    private static let size = CGSize(width: 706, height: 470)
    private static let inset: CGFloat = 14
    static let width = size.width + inset * 2

    // Where everything sits, in the machine's own points, mirrored about the middle.
    private static let leftHinge = CGRect(x: 40, y: 16, width: 96, height: 14)
    private static let rightHinge = CGRect(x: 570, y: 16, width: 96, height: 14)
    private static let vent = CGRect(x: 148, y: 17, width: 410, height: 12)
    /// The fin stack above, the housing below it, round at its foot.
    private static let leftFan = CGRect(x: 20, y: 40, width: 140, height: 158)
    private static let rightFan = CGRect(x: 546, y: 40, width: 140, height: 158)
    /// The logic board: up between the fans from `boardTop`, and right across under
    /// them to `boardBottom`, its edge running `boardGap` clear of each fan's housing.
    private static let boardTop: CGFloat = 40
    private static let boardBottom: CGFloat = 292
    private static let boardGap: CGFloat = 8
    /// The bento's parts at the sizes their cards draw them, and where they sit here:
    /// the chips centred on the fans' hubs, a thermometer on the outer side of each.
    private static let chipNative = CGSize(width: 140, height: 140)
    private static let gpuNative = CGSize(width: 200, height: 106)
    private static let memoryNative = CGSize(width: 200, height: 56)
    private static let ssdNative = CGSize(width: 200, height: 44)
    private static let cpu = CGRect(x: 206, y: 70, width: 116, height: 116)
    private static let gpu = CGRect(x: 338, y: 85.07, width: 162, height: 85.86)
    private static let cpuThermometer = CGRect(x: 174, y: 74, width: 26, height: 108)
    private static let gpuThermometer = CGRect(x: 506, y: 74, width: 26, height: 108)
    /// The module and the drive at one scale, centred on one line, and the Wi-Fi module,
    /// pins and all, between them.
    private static let memory = CGRect(x: 22, y: 216, width: 152, height: 42.56)
    private static let ssd = CGRect(x: 532, y: 220.56, width: 152, height: 33.44)
    private static let wifi = CGRect(x: 272, y: 208.28, width: 162, height: 58)
    private static let leftSpeaker = CGRect(x: 20, y: 304, width: 28, height: 150)
    private static let leftCells = CGRect(x: 58, y: 304, width: 168, height: 150)
    private static let trackpad = CGRect(x: 238, y: 304, width: 230, height: 150)
    private static let rightCells = CGRect(x: 480, y: 304, width: 168, height: 150)
    private static let rightSpeaker = CGRect(x: 658, y: 304, width: 28, height: 150)
    /// Where the labels under the memory and the SSD start.
    private static let labelsTop: CGFloat = 267

    private var formatter: MetricFormatter {
        MetricFormatter(settings: settings.settings.general)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            chassis
            hinge
            board
            fans
            heatPipes
            chips
            modules
            readings
            battery
            trackpadInfo
            speakers
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .padding(Self.inset)
        .environment(\.metricFormatter, formatter)
    }

    // MARK: Case

    private var chassis: some View {
        let shell = RoundedRectangle(cornerRadius: 34, style: .continuous)
        let floor = RoundedRectangle(cornerRadius: 27, style: .continuous)
        return canvas {
            shell.fill(LinearGradient(colors: [Tone.rimTop, Tone.rim], startPoint: .top, endPoint: .bottom))
            shell.strokeBorder(Tone.edge, lineWidth: 1)
            floor.fill(Tone.floor).padding(8)
            ports
        }
    }

    /// Cut into the sides: MagSafe, two Thunderbolt ports and the headphone jack on the
    /// left, HDMI, Thunderbolt and the SD slot on the right.
    private var ports: some View {
        let left = [CGRect(x: 2, y: 96, width: 4, height: 24), CGRect(x: 2, y: 136, width: 4, height: 14),
                    CGRect(x: 2, y: 160, width: 4, height: 14), CGRect(x: 2, y: 192, width: 4, height: 6)]
        let right = [CGRect(x: 700, y: 98, width: 4, height: 20), CGRect(x: 700, y: 136, width: 4, height: 14),
                     CGRect(x: 700, y: 166, width: 4, height: 30)]
        return ForEach(Array((left + right).enumerated()), id: \.offset) { _, rect in
            place(RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(Tone.port), rect)
        }
    }

    /// The display's hinges at either end and the exhaust between them. The App Store's
    /// copy, which reads no fan, has macOS's thermal state printed in the middle instead.
    private var hinge: some View {
        let barrel = ZStack {
            Capsule().fill(LinearGradient(colors: [Tone.partTop, Tone.part], startPoint: .top, endPoint: .bottom))
            Capsule().strokeBorder(Tone.edge, lineWidth: 1)
        }
        let state = Capabilities.readsSensors ? nil : engine.thermal.value?.pressure
        return canvas {
            place(barrel, Self.leftHinge)
            place(barrel, Self.rightHinge)
            if let state {
                let gap: CGFloat = 150
                let run = (Self.vent.width - gap) / 2
                place(VentSlots().fill(Tone.vent),
                      CGRect(x: Self.vent.minX, y: Self.vent.minY, width: run, height: Self.vent.height))
                place(VentSlots().fill(Tone.vent),
                      CGRect(x: Self.vent.maxX - run, y: Self.vent.minY, width: run, height: Self.vent.height))
                HStack(spacing: Design.Space.s) {
                    caption("Thermal state")
                    Text(Self.stateWord(state))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(gradient(Self.stateColors(state)))
                }
                .fixedSize()
                .hoverRegion(.thermal, layout: layout)
                .position(x: Self.vent.midX, y: Self.vent.midY)
            } else {
                place(VentSlots().fill(Tone.vent), Self.vent)
            }
        }
    }

    // MARK: Fans

    /// Each fan with how fast it is going on its hub. A Mac without fans has "None" on
    /// the left one; the App Store's copy, which cannot read them, has nothing: its
    /// blades are the drawing's, not a reading.
    private var fans: some View {
        let fans = engine.thermal.value?.fans ?? []
        let left = fanSpeed(fans.first) ?? (Capabilities.readsSensors ? "None" : nil)
        return canvas {
            place(fan(fans.first, isMirrored: false, speed: left).hoverRegion(.thermal, layout: layout),
                  Self.leftFan)
            place(fan(fans.count > 1 ? fans[1] : fans.first, isMirrored: true,
                      speed: fans.count > 1 ? fanSpeed(fans[1]) : nil)
                .hoverRegion(.thermal, layout: layout), Self.rightFan)
        }
    }

    private func fanSpeed(_ fan: FanInfo?) -> String? {
        fan.map { $0.currentRPM < 1 ? "Off" : formatter.percent($0.speedFraction) }
    }

    /// The fin stack the fan blows through, and the fan in its housing: square where it
    /// meets the fins, round where it wraps the blades, its speed on a cap over the hub
    /// that stays still while the blades turn.
    private func fan(_ fan: FanInfo?, isMirrored: Bool, speed: String?) -> some View {
        let fins = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let radius = Self.leftFan.width / 2
        let housing = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 6, bottomLeading: radius,
                                                                bottomTrailing: radius, topTrailing: 6),
                                             style: .circular)
        return VStack(spacing: -2) {
            ZStack {
                fins.fill(Tone.well)
                VentSlots(pitch: 3.2).fill(Copper.fins).padding(.vertical, 2)
                fins.strokeBorder(Tone.edge, lineWidth: 0.75)
            }
            .frame(height: 18)
            ZStack(alignment: .bottom) {
                housing.fill(LinearGradient(colors: [Tone.partTop, Tone.part], startPoint: .top, endPoint: .bottom))
                housing.strokeBorder(Tone.edge, lineWidth: 1)
                ZStack {
                    Circle().fill(Tone.well)
                    SpinningFan(fraction: fan?.speedFraction ?? 0, isSpinning: (fan?.currentRPM ?? 0) >= 1,
                                isMirrored: isMirrored)
                        .frame(width: 114, height: 114)
                    if let speed {
                        Text(speed)
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(gradient(Self.fanColors))
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Tone.well))
                            .overlay(Circle().strokeBorder(Tone.edge, lineWidth: 1))
                    }
                }
                .frame(width: 124, height: 124)
                .padding(.bottom, radius - 62)
                HStack {
                    screw
                    Spacer()
                    screw
                }
                .padding(.horizontal, 9)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 9)
            }
        }
    }

    // MARK: Board

    private var board: some View {
        let outline = BoardOutline(top: Self.boardTop, bottom: Self.boardBottom, leftFan: Self.leftFan,
                                   rightFan: Self.rightFan, gap: Self.boardGap, radius: 12)
        return canvas {
            outline.fill(LinearGradient(colors: [Tone.boardTop, Tone.board], startPoint: .top, endPoint: .bottom))
            outline.stroke(Tone.edge, lineWidth: 1)
            BoardTraces(buses: Self.traces)
                .stroke(Tone.trace, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            BoardParts(kind: .capacitors).fill(Tone.component)
            BoardParts(kind: .chips).fill(Tone.boardChip)
            BoardParts(kind: .chips).stroke(Color.white.opacity(0.14), lineWidth: 0.75)
        }
    }

    /// The traces, run in under the parts' edges: the GPU's left pins straight across
    /// into the CPU; buses up into the CPU's foot from the memory, from the Wi-Fi
    /// module's pins and, along under the GPU, from the SSD; and three of the GPU's pins
    /// down to its power controller. Pins are where `ChipLegs` sets them: 8pt apart from
    /// 12pt in, at the GPU's scale.
    private static let traces: [BoardTraces.Bus] = {
        let gpuScale = gpu.width / gpuNative.width
        let gpuPinsMiddle = gpu.minY + (12 + 8 * 5) * gpuScale
        let wifiPinsMiddle = wifi.minY + 12 + 8
        let street: CGFloat = 196
        return [
            BoardTraces.Bus(route: [CGPoint(x: cpu.maxX - 4, y: gpuPinsMiddle),
                                    CGPoint(x: gpu.minX + 4, y: gpuPinsMiddle)],
                            count: 11, pitch: 8 * gpuScale),
            BoardTraces.Bus(route: [CGPoint(x: memory.maxX - 4, y: memory.midY - 1), CGPoint(x: 200, y: memory.midY - 1),
                                    CGPoint(x: 221, y: memory.midY - 22), CGPoint(x: 221, y: cpu.maxY - 4)],
                            count: 4, pitch: 6),
            BoardTraces.Bus(route: [CGPoint(x: wifi.minX + 4, y: wifiPinsMiddle), CGPoint(x: 262, y: wifiPinsMiddle),
                                    CGPoint(x: 250, y: wifiPinsMiddle - 12), CGPoint(x: 250, y: cpu.maxY - 4)],
                            count: 3, pitch: 8),
            BoardTraces.Bus(route: [CGPoint(x: ssd.minX + 4, y: ssd.midY), CGPoint(x: 482, y: ssd.midY),
                                    CGPoint(x: 482 - (ssd.midY - street), y: street), CGPoint(x: 316, y: street),
                                    CGPoint(x: 306, y: street - 10), CGPoint(x: 306, y: cpu.maxY - 4)],
                            count: 3, pitch: 5),
            BoardTraces.Bus(route: [CGPoint(x: gpu.minX + (12 + 8 * 21) * gpuScale, y: gpu.maxY - 4),
                                    CGPoint(x: gpu.minX + (12 + 8 * 21) * gpuScale, y: 194)],
                            count: 3, pitch: 8 * gpuScale),
        ]
    }()

    /// Copper, thicker than before, from the fan's outer edge right along the foot of its
    /// fins, down in an S over the board, and along the top edge of the chip it cools: the
    /// CPU on the left, the GPU on the right.
    private var heatPipes: some View {
        let pipes = [HeatPipe(from: CGPoint(x: 26, y: 52), leaves: 200, lands: 236,
                              to: CGPoint(x: Self.cpu.maxX - 6, y: Self.cpu.minY - 3)),
                     HeatPipe(from: CGPoint(x: 680, y: 52), leaves: 506, lands: 470,
                              to: CGPoint(x: Self.gpu.minX + 6, y: Self.gpu.minY - 3))]
        return canvas {
            ForEach(pipes.indices, id: \.self) { index in
                pipes[index].stroke(Color.black.opacity(0.2),
                                    style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    .offset(y: 1.5)
                pipes[index].stroke(Copper.pipe, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                pipes[index].stroke(Copper.shine.opacity(0.8),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .offset(y: -2.5)
            }
        }
    }

    // MARK: Chips

    /// The bento's CPU chip, its cores lit by their load, and its GPU, its cores switching
    /// on as the load rises, side by side where the heat pipes end: each with its load
    /// under its name, and its temperature on a thermometer on its outer side.
    private var chips: some View {
        let cpu = engine.cpu.value
        let kinds = cpu?.coreKinds ?? []
        let loads = cpu?.perCore.map(\.busy) ?? []
        // A core the system did not classify is drawn as a performance core: that is what
        // a chip without the split has.
        let performance = loads.indices.filter { $0 >= kinds.count || kinds[$0] != .efficiency }.map { loads[$0] }
        let efficiency = loads.indices.filter { $0 < kinds.count && kinds[$0] == .efficiency }.map { loads[$0] }
        let device = engine.gpu.value?.primary
        let thermal = engine.thermal.value
        return canvas {
            place(scaled(ChipGraphic(name: engine.system.value?.chipName,
                                     performance: performance, efficiency: efficiency,
                                     performanceColors: [.white, .white],
                                     efficiencyColors: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)],
                                     reading: cpu.map { formatter.percent($0.total.busy) } ?? MetricFormatter.unavailable),
                         native: Self.chipNative, width: Self.cpu.width)
                .shadow(color: Tone.dropShadow, radius: 3, y: 1)
                .hoverRegion(.cpu, layout: layout), Self.cpu)
            place(gpuDie(cores: device?.coreCount ?? engine.system.value?.gpuCoreCount ?? 0,
                         load: device?.utilization ?? 0,
                         reading: device?.utilization.map { formatter.percent($0) } ?? MetricFormatter.unavailable)
                .shadow(color: Tone.dropShadow, radius: 3, y: 1)
                .hoverRegion(.gpu, layout: layout), Self.gpu)
            place(thermometer(thermal?.cpuCelsius).hoverRegion(.cpu, layout: layout), Self.cpuThermometer)
            place(thermometer(thermal?.gpuCelsius).hoverRegion(.gpu, layout: layout), Self.gpuThermometer)
        }
    }

    @ViewBuilder
    private func gpuDie(cores: Int, load: Double, reading: String) -> some View {
        if cores > 0 {
            scaled(GPUDie(cores: cores, load: load, colors: palette(.gpu), size: Self.gpuNative, reading: reading),
                   native: Self.gpuNative, width: Self.gpu.width)
        } else {
            // No core count to lay the cores out by: the package, its name and its load.
            ZStack {
                ChipFace()
                VStack(spacing: 0) {
                    Text("GPU")
                        .font(.system(size: 29, weight: .semibold))
                        .tracking(1.4)
                    Text(reading)
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(ChipGraphic.silver)
            }
            .padding(4)
        }
    }

    /// A chip's temperature on a thermometer standing beside it, as the bento's
    /// temperature cards draw them, with the figure under the bulb. Nothing where there
    /// is no sensor to read, as in the App Store's copy.
    @ViewBuilder
    private func thermometer(_ celsius: Double?) -> some View {
        if let celsius {
            VStack(spacing: 3) {
                ThermometerGraphic(fraction: min(max((celsius - 30) / 70, 0), 1), colors: Self.heatColors,
                                   scale: 0.6)
                    .frame(width: 17)
                Text(formatter.temperature(celsius))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(gradient(Self.heatColors))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    // MARK: Memory and SSD

    /// The bento's memory module standing in its slot under the left fan, and its SSD in
    /// its socket under the right, held down by the screw at its far end: each filled by
    /// how full it is, with what is free printed on it.
    private var modules: some View {
        let memory = engine.memory.value
        let root = engine.disk.value?.rootVolume
        let scale = Self.memory.width / Self.memoryNative.width
        let slot = RoundedRectangle(cornerRadius: 2, style: .continuous)
        let socket = ZStack {
            slot.fill(Tone.well)
            slot.strokeBorder(Tone.edge, lineWidth: 0.75)
        }
        // Free is what the fill leaves, and the drive's fill is counted from the same
        // available space as the label printed on it, as the bento counts them.
        let memoryFree = memory.map { $0.totalBytes > $0.usedBytes ? $0.totalBytes - $0.usedBytes : 0 }
        let memoryUsed = memory.map { $0.totalBytes > 0 ? Double($0.usedBytes) / Double($0.totalBytes) : 0 }
        let diskUsed = root.map { $0.totalBytes > 0 ? 1 - Double($0.availableBytes) / Double($0.totalBytes) : 0 }
        return canvas {
            place(socket, CGRect(x: Self.memory.minX - 4, y: Self.memory.maxY - 8 * scale - 2,
                                 width: Self.memory.width + 8, height: 8 * scale + 5))
            place(scaled(MemoryGraphic(label: memoryFree.map { "\(formatter.memory($0)) free" },
                                       fraction: memoryUsed ?? 0, load: palette(.memory)[0]),
                         native: Self.memoryNative, width: Self.memory.width)
                .shadow(color: Tone.dropShadow, radius: 2, y: 1)
                .hoverRegion(.memory, layout: layout), Self.memory)
            place(socket, CGRect(x: Self.ssd.minX - 4, y: Self.ssd.minY - 3,
                                 width: 9 * scale + 6, height: Self.ssd.height + 6))
            place(scaled(SSDGraphic(fraction: diskUsed ?? 0, colors: palette(.disk),
                                    label: root.map { "\(formatter.storage($0.availableBytes)) free" },
                                    surface: Tone.board),
                         native: Self.ssdNative, width: Self.ssd.width)
                .shadow(color: Tone.dropShadow, radius: 2, y: 1)
                .hoverRegion(.disk, layout: layout), Self.ssd)
            screw.position(x: Self.ssd.maxX, y: Self.ssd.midY)
        }
    }

    // MARK: Readings

    /// The labels under the memory and the SSD, and the Wi-Fi module between them.
    private var readings: some View {
        let thermal = engine.thermal.value
        let memory = engine.memory.value
        let root = engine.disk.value?.rootVolume
        return canvas {
            label("Memory", memory.map { formatter.memory($0.totalBytes) })
                .hoverRegion(.memory, layout: layout)
                .top(at: CGPoint(x: Self.memory.midX, y: Self.labelsTop))
            place(network.hoverRegion(.network, layout: layout), Self.wifi)
            label("SSD", root.map { formatter.storage($0.totalBytes) }, celsius: Self.hottest(thermal, .storage))
                .hoverRegion(.disk, layout: layout)
                .top(at: CGPoint(x: Self.ssd.midX, y: Self.labelsTop))
        }
    }

    /// The Wi-Fi module drawn as the bento draws its chips, a dark package on gold pins,
    /// with what is going up and coming down printed on it, as the bento's network card
    /// sets them.
    private var network: some View {
        let network = engine.network.value ?? engine.lastKnown.network.value
        let leg: CGFloat = 4
        return ZStack {
            ChipLegs(leg: leg).fill(ChipLegs.gold)
            ChipFace().padding(leg)
            HStack(spacing: 0) {
                Image(systemName: network?.wifi != nil || network == nil ? "wifi" : "network")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(gradient(palette(.network)))
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("↑ " + (network.map { formatter.networkRate($0.uploadBytesPerSecond) } ?? MetricFormatter.unavailable))
                        .foregroundStyle(gradient(Self.upColors))
                    Text("↓ " + (network.map { formatter.networkRate($0.downloadBytesPerSecond) } ?? MetricFormatter.unavailable))
                        .foregroundStyle(gradient(Self.downColors))
                }
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, leg + 8)
        }
        .shadow(color: Tone.dropShadow, radius: 2, y: 1)
    }

    /// A part's reading: what it is in small capitals, the figure in the part's colours,
    /// and under it the part's temperature where it has a sensor.
    private func reading(_ title: String, _ value: String?, colors: [Color], size: CGFloat = 16,
                         celsius: Double? = nil) -> some View {
        VStack(spacing: 1) {
            caption(title)
            Text(value ?? MetricFormatter.unavailable)
                .font(.system(size: size, weight: .bold).monospacedDigit())
                .foregroundStyle(gradient(colors))
                .contentTransition(.numericText())
            if let celsius {
                temperature(celsius)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// A part's name in small capitals and what it holds beside it, under a part that
    /// carries its own reading.
    private func label(_ title: String, _ detail: String?, celsius: Double? = nil) -> some View {
        HStack(spacing: 5) {
            caption(title)
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Design.Palette.secondaryText)
            }
            if let celsius {
                temperature(celsius)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func temperature(_ celsius: Double) -> some View {
        HStack(spacing: 1) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 9, weight: .bold))
            Text(formatter.temperature(celsius))
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(gradient(Self.heatColors))
    }

    private func caption(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Design.Palette.secondaryText)
            .lineLimit(1)
    }

    // MARK: Battery, trackpad and speakers

    /// Three cells either side of the trackpad, each filled by the pack's charge, red when
    /// low. The middle cell on each side carries the pack's label: the charge on the left,
    /// what the power is doing on the right.
    private var battery: some View {
        let power = engine.power.value
        let charge = (power?.percentage ?? 0) / 100
        let isLow = power != nil && charge <= 0.2 && power?.isCharging == false
        let colors = isLow ? Self.heatColors : palette(.battery)
        let state = power.map(powerState)
        return canvas {
            place(cells(charge: charge, color: colors[0], tabsTrailing: true) {
                reading("Battery", power?.percentage.map { formatter.percentValue($0) }, colors: colors,
                        size: 17, celsius: power?.temperatureCelsius ?? Self.hottest(engine.thermal.value, .battery))
            }
            .hoverRegion(.battery, layout: layout), Self.leftCells)
            place(cells(charge: charge, color: colors[0], tabsTrailing: false) {
                reading(state?.title ?? "Power", state?.value, colors: colors, size: 15)
            }
            .hoverRegion(.battery, layout: layout), Self.rightCells)
        }
    }

    private func cells<Label: View>(charge: Double, color: Color, tabsTrailing: Bool,
                                    @ViewBuilder label: () -> Label) -> some View {
        let sticker = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return VStack(spacing: 8) {
            cell(charge: charge, color: color, tabsTrailing: tabsTrailing)
            cell(charge: charge, color: color, tabsTrailing: tabsTrailing)
                .overlay {
                    label()
                        .padding(.horizontal, Design.Space.l)
                        .padding(.vertical, 5)
                        .background(sticker.fill(Tone.sticker))
                        .overlay(sticker.strokeBorder(Tone.edge, lineWidth: 0.75))
                        .shadow(color: Tone.dropShadow, radius: 1.5, y: 0.5)
                }
            cell(charge: charge, color: color, tabsTrailing: tabsTrailing)
        }
    }

    /// One cell: the pouch, filled with the charge from its outer end, and at the end that
    /// faces the trackpad the strip its tabs come out of.
    private func cell(charge: Double, color: Color, tabsTrailing: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let tabs = ZStack {
            Rectangle().fill(Tone.well)
            VStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(LinearGradient(colors: [Tone.screwTop, Tone.screw], startPoint: .top, endPoint: .bottom))
                        .frame(width: 6, height: 9)
                }
            }
        }
        .frame(width: 13)
        return ZStack {
            shape.fill(LinearGradient(colors: [Tone.partTop, Tone.part], startPoint: .top, endPoint: .bottom))
            HStack(spacing: 0) {
                if !tabsTrailing { tabs }
                ZStack {
                    FillFromLeading(fraction: charge)
                        .fill(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.22)],
                                             startPoint: .leading, endPoint: .trailing))
                    LevelLine(fraction: charge, vertical: false).fill(color)
                }
                .scaleEffect(x: tabsTrailing ? 1 : -1)
                if tabsTrailing { tabs }
            }
            .clipShape(shape)
            shape.strokeBorder(Tone.edge, lineWidth: 1)
        }
        .shadow(color: Tone.dropShadow, radius: 2, y: 1)
        .animation(Design.Motion.respectingAccessibility(Design.Motion.value), value: charge)
    }

    /// What the power is doing, and for how long, where the system says.
    private func powerState(_ power: PowerSnapshot) -> (title: String, value: String) {
        guard power.hasBattery else { return ("Power", "Adapter") }
        if power.isCharging {
            return power.timeToFull.map { ("Charging", "Full in \(formatter.duration($0))") } ?? ("Power", "Charging")
        }
        if power.isFullyCharged { return ("Power", "Charged") }
        if power.isPluggedIn { return ("Power", "Plugged in") }
        return power.timeToEmpty.map { ("On battery", "\(formatter.duration($0)) left") } ?? ("Power", "On battery")
    }

    /// The trackpad, with what the machine is written on it.
    private var trackpadInfo: some View {
        let system = engine.system.value
        let model = system.map(BentoGrid.model)
        let pad = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return place(ZStack {
            pad.fill(LinearGradient(colors: [Tone.glassTop, Tone.glass], startPoint: .top, endPoint: .bottom))
            pad.strokeBorder(Tone.edge, lineWidth: 1)
            VStack(spacing: 3) {
                Text(model?.name ?? "MacBook")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Design.Palette.primaryText)
                if let detail = model?.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Design.Palette.secondaryText)
                }
                if let system {
                    Text("\(system.osName) \(system.osVersion)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Design.Palette.secondaryText)
                    Text("Up \(formatter.uptime(system.uptime))")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Design.Palette.tertiaryText)
                        .padding(.top, 4)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Design.Space.l)
        }
        .shadow(color: Tone.dropShadow, radius: 2, y: 1)
        .hoverRegion(.system, layout: layout), Self.trackpad)
    }

    private var speakers: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let speaker = ZStack {
            shape.fill(LinearGradient(colors: [Tone.partTop, Tone.part], startPoint: .top, endPoint: .bottom))
            DotGrid(pitch: 5, radius: 1.1).fill(Tone.well).padding(6)
            shape.strokeBorder(Tone.edge, lineWidth: 1)
        }
        return canvas {
            place(speaker, Self.leftSpeaker)
            place(speaker, Self.rightSpeaker)
        }
    }

    // MARK: Pieces

    /// What holds a part down: a Phillips head.
    private var screw: some View {
        let slot = Capsule().fill(Tone.well)
        return ZStack {
            Circle().fill(LinearGradient(colors: [Tone.screwTop, Tone.screw], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(Tone.edge, lineWidth: 0.75)
            slot.frame(width: 5.5, height: 1.6)
            slot.frame(width: 1.6, height: 5.5)
        }
        .frame(width: 10, height: 10)
    }

    /// The whole machine's area, for layers drawn in its own points.
    private func canvas<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .topLeading, content: content)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    /// Sets a part at its place by layout rather than by offset, so the frame it reports
    /// for the detail beside the panel is where it is drawn.
    private func place<V: View>(_ view: V, _ rect: CGRect) -> some View {
        view.frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
    }

    /// One of the bento's parts drawn at the size its card draws it and scaled to `width`,
    /// so it keeps the card's proportions, lettering and all.
    private func scaled<V: View>(_ part: V, native: CGSize, width: CGFloat) -> some View {
        let scale = width / native.width
        return part
            .frame(width: native.width, height: native.height)
            .scaleEffect(scale)
            .frame(width: width, height: native.height * scale)
    }

    private func palette(_ module: PanelModule) -> [Color] {
        BentoGrid.palette(module)
    }

    private func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private static let fanColors = [Color(nsColor: .systemCyan), Color(nsColor: .systemBlue)]
    private static let heatColors = [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)]
    private static let upColors = [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)]
    private static let downColors = [Color(nsColor: .systemBlue), Color(nsColor: .systemCyan)]

    private static func hottest(_ thermal: ThermalSnapshot?, _ category: SensorCategory) -> Double? {
        thermal?.sensors.filter { $0.category == category }.map(\.celsius).max()
    }

    /// The bento's words and colours for macOS's thermal states.
    private static func stateWord(_ state: ThermalPressure) -> String {
        switch state {
        case .nominal: "Normal"
        case .fair: "Elevated"
        case .serious: "High"
        case .critical: "Critical"
        }
    }

    private static func stateColors(_ state: ThermalPressure) -> [Color] {
        switch state {
        case .nominal: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)]
        case .fair: [Color(nsColor: .systemYellow), Color(nsColor: .systemOrange)]
        case .serious: [Color(nsColor: .systemOrange), Color(nsColor: .systemRed)]
        case .critical: [Color(nsColor: .systemRed), Color(nsColor: .systemPink)]
        }
    }

    /// One neutral in steps of dark graphite, for everything that is not data. Dark only:
    /// the panel is always dark while it draws the MacBook (see `PanelController.show`).
    private enum Tone {
        private static func shade(_ white: CGFloat, alpha: CGFloat = 1) -> Color {
            Color(nsColor: NSColor(white: white, alpha: alpha))
        }

        static let rimTop = shade(0.24)
        static let rim = shade(0.16)
        static let floor = shade(0.095)
        static let boardTop = shade(0.135)
        static let board = shade(0.115)
        /// Darker than the board, so the traces read as cut into it.
        static let trace = shade(0.07)
        static let partTop = shade(0.235)
        static let part = shade(0.195)
        static let well = shade(0.11)
        static let glassTop = shade(0.15)
        static let glass = shade(0.115)
        static let sticker = shade(0.15, alpha: 0.94)
        static let screwTop = shade(0.48)
        static let screw = shade(0.30)
        static let component = shade(0.25)
        static let boardChip = shade(0.10)
        static let vent = shade(0.03)
        static let port = shade(0.02)
        static let edge = shade(1, alpha: 0.13)
        static let dropShadow = shade(0, alpha: 0.45)
    }

    /// The heat pipes and the fins they run through.
    private enum Copper {
        static let pipe = LinearGradient(colors: [Color(red: 0.86, green: 0.55, blue: 0.32),
                                                  Color(red: 0.66, green: 0.38, blue: 0.20)],
                                         startPoint: .top, endPoint: .bottom)
        static let shine = Color(red: 0.98, green: 0.76, blue: 0.55)
        static let fins = LinearGradient(colors: [Color(red: 0.85, green: 0.58, blue: 0.38),
                                                  Color(red: 0.60, green: 0.36, blue: 0.22)],
                                         startPoint: .top, endPoint: .bottom)
    }
}

private extension View {
    /// Sets a reading with the middle of its top edge at `point`, so readings of one,
    /// two or three lines line up along their tops.
    func top(at point: CGPoint) -> some View {
        frame(width: 160, height: 80, alignment: .top)
            .position(x: point.x, y: point.y + 40)
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
///
/// A Mac's two fans are drawn as each other's reflection: the second one's blades curve
/// the other way, and it turns anticlockwise.
struct SpinningFan: View {
    /// 0...1, idle to flat out.
    let fraction: Double
    let isSpinning: Bool
    var isMirrored = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds per turn, in steps, so a fan that wavers by a few RPM keeps its pace.
    private var period: Double {
        let step = (min(max(fraction, 0), 1) * 6).rounded() / 6
        return 2.6 - 2.1 * step
    }

    var body: some View {
        let period = isSpinning && !reduceMotion ? self.period : nil
        // A new rotor at each new pace, which starts turning from rest. The angle cannot
        // live here: set back to 0 and on to 360 in one update, it would not change at
        // all, and the fan would stop at the first change of pace.
        FanRotor(period: period, isMirrored: isMirrored)
            .id(period ?? 0)
    }
}

private struct FanRotor: View {
    let period: Double?
    let isMirrored: Bool

    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            FanBlades().fill(Color.white.opacity(0.38))
            FanBlades().stroke(Color.black.opacity(0.15), lineWidth: 0.5)
            Circle().fill(Color(white: 0.35)).frame(width: 34, height: 34)
            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1).frame(width: 34, height: 34)
        }
        .scaleEffect(x: isMirrored ? -1 : 1)
        .rotationEffect(.degrees(angle))
        .onAppear {
            guard let period else { return }
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                angle = isMirrored ? -360 : 360
            }
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

/// A heat pipe: straight along from the fins, down in an S from `leaves` to `lands`, and
/// straight on along the chip's top edge to its end.
private struct HeatPipe: Shape {
    let from: CGPoint
    let leaves: CGFloat
    let lands: CGFloat
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let middle = (leaves + lands) / 2
        path.move(to: from)
        path.addLine(to: CGPoint(x: leaves, y: from.y))
        path.addCurve(to: CGPoint(x: lands, y: to.y), control1: CGPoint(x: middle, y: from.y),
                      control2: CGPoint(x: middle, y: to.y))
        path.addLine(to: to)
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

/// The logic board's outline: up between the fans and right across under them, its
/// edge running `gap` clear of each housing, down its sides and round its foot, which
/// is half a circle as wide as the fan.
///
/// Where the curve round a fan comes back up to the board's outer side, the two would
/// meet in a point; a corner of `radius` rounds it off before they do.
private struct BoardOutline: Shape {
    let top: CGFloat
    let bottom: CGFloat
    let leftFan: CGRect
    let rightFan: CGRect
    let gap: CGFloat
    /// The board's own corners, and those where its sides meet the curves.
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let left = leftFan.insetBy(dx: -gap, dy: -gap)
        let right = rightFan.insetBy(dx: -gap, dy: -gap)
        let leftHub = CGPoint(x: leftFan.midX, y: leftFan.maxY - leftFan.width / 2)
        let rightHub = CGPoint(x: rightFan.midX, y: rightFan.maxY - rightFan.width / 2)
        let cut = left.width / 2
        // The rounding corner's centre: `radius` in from the side, and `radius` clear of the
        // curve, so it touches both.
        func corner(hub: CGPoint, side: CGFloat) -> CGPoint {
            let x = side + (side < hub.x ? radius : -radius)
            return CGPoint(x: x, y: hub.y + sqrt(pow(cut + radius, 2) - pow(x - hub.x, 2)))
        }
        // Angles in radians with y down the screen, each arc swept the short way: the
        // curves through the foot of each fan, the rounding corners over their tops.
        func angle(from a: CGPoint, to b: CGPoint) -> Double { atan2(b.y - a.y, b.x - a.x) }
        let leftCorner = corner(hub: leftHub, side: left.minX)
        let rightCorner = corner(hub: rightHub, side: right.maxX)

        var path = Path()
        path.move(to: CGPoint(x: (left.maxX + right.minX) / 2, y: top))
        path.addArc(tangent1End: CGPoint(x: right.minX, y: top), tangent2End: CGPoint(x: right.minX, y: rightHub.y),
                    radius: radius)
        path.addArc(center: rightHub, radius: cut, startAngle: .radians(.pi),
                    endAngle: .radians(angle(from: rightHub, to: rightCorner)), clockwise: true)
        path.addArc(center: rightCorner, radius: radius, startAngle: .radians(angle(from: rightCorner, to: rightHub)),
                    endAngle: .zero, clockwise: false)
        path.addArc(tangent1End: CGPoint(x: right.maxX, y: bottom), tangent2End: CGPoint(x: left.minX, y: bottom),
                    radius: radius)
        path.addArc(tangent1End: CGPoint(x: left.minX, y: bottom), tangent2End: CGPoint(x: left.minX, y: leftHub.y),
                    radius: radius)
        path.addArc(center: leftCorner, radius: radius, startAngle: .radians(.pi),
                    endAngle: .radians(angle(from: leftCorner, to: leftHub) + 2 * .pi), clockwise: false)
        path.addArc(center: leftHub, radius: cut, startAngle: .radians(angle(from: leftHub, to: leftCorner)),
                    endAngle: .zero, clockwise: true)
        path.addArc(tangent1End: CGPoint(x: left.maxX, y: top), tangent2End: CGPoint(x: right.minX, y: top),
                    radius: radius)
        path.closeSubpath()
        return path
    }
}

/// The board's traces: buses of thin lines running square and at 45°, each trace kept
/// its pitch from the next round every bend, as a board's traces are routed.
private struct BoardTraces: Shape {
    /// A bus: the line down its middle, how many traces it carries, and how far apart.
    struct Bus {
        let route: [CGPoint]
        let count: Int
        let pitch: CGFloat
    }

    let buses: [Bus]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for bus in buses {
            for index in 0..<bus.count {
                path.addLines(Self.offset(bus.route, by: (CGFloat(index) - CGFloat(bus.count - 1) / 2) * bus.pitch))
            }
        }
        return path
    }

    /// `route` moved `distance` to one side, square to each of its runs: at each bend, to
    /// where the two moved runs cross.
    private static func offset(_ route: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        let normals = zip(route, route.dropFirst()).map { a, b in
            let length = hypot(b.x - a.x, b.y - a.y)
            return CGVector(dx: (a.y - b.y) / length, dy: (b.x - a.x) / length)
        }
        return route.indices.map { index in
            let before = normals[max(index - 1, 0)]
            let after = normals[min(index, normals.count - 1)]
            let scale = distance / (1 + before.dx * after.dx + before.dy * after.dy)
            return CGPoint(x: route[index].x + (before.dx + after.dx) * scale,
                           y: route[index].y + (before.dy + after.dy) * scale)
        }
    }
}

/// The small parts around a logic board's big ones, at fixed places so the board looks
/// the same every time it is drawn, clear of the traces: the GPU's power controller
/// under it, and either side of the Wi-Fi module a controller, a smaller part and a row
/// of capacitors.
private struct BoardParts: Shape {
    enum Kind { case chips, capacitors }

    let kind: Kind

    /// In the machine's points.
    private static let chips = [CGRect(x: 471, y: 190, width: 26, height: 20),
                                CGRect(x: 190, y: 252, width: 24, height: 24),
                                CGRect(x: 226, y: 256, width: 16, height: 11),
                                CGRect(x: 492, y: 252, width: 24, height: 24),
                                CGRect(x: 464, y: 256, width: 16, height: 11)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard kind == .capacitors else {
            for chip in Self.chips {
                path.addRoundedRect(in: chip, cornerSize: CGSize(width: 1.5, height: 1.5))
            }
            return path
        }
        for x in Array(stride(from: CGFloat(226), through: 254, by: 7)) + Array(stride(from: CGFloat(450), through: 478, by: 7)) {
            path.addRoundedRect(in: CGRect(x: x, y: 280, width: 2.5, height: 4), cornerSize: CGSize(width: 0.5, height: 0.5))
        }
        return path
    }
}

/// Holes in rows, each row half a pitch along from the last: a speaker's grille.
private struct DotGrid: Shape {
    let pitch: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var row = 0
        var y = rect.minY + radius
        while y <= rect.maxY - radius {
            var x = rect.minX + radius + (row.isMultiple(of: 2) ? 0 : pitch / 2)
            while x <= rect.maxX - radius {
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                x += pitch
            }
            y += pitch * 0.87
            row += 1
        }
        return path
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
