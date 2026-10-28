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
/// the logic board up the middle, with heat pipes from the fins to the CPU and the GPU,
/// and across under the fans for the memory in its slot, the Wi-Fi module and the SSD
/// in its socket; then the battery's cells either side of the trackpad, a speaker at
/// each edge, and the ports along the sides.
///
///     ┌── hinge ────────────────── vents ────────────────── hinge ──┐
///     │ ┌ fins ┐  ┌─────────── logic board ───────────┐  ┌ fins ┐ │
///     │ │ fan  │  │  ┌ CPU ┐      ┌──── GPU ────┐     │  │ fan  │ │
///     │ ╰──────╯  │  └─────┘      └─────────────┘     │  ╰──────╯ │
///     │   27%     │    34%             18%            │    26%    │
///     │ ┌─────────┘                                   └─────────┐ │
///     │ │ memory: 7.7 GB free   Wi-Fi ↑ ↓   SSD: 185 GB free    │ │
///     │ └───────────────────────────────────────────────────────┘ │
///     │ ┌─┐┌ cells ┐ ┌──────── trackpad ────────┐ ┌ cells ┐┌─┐ │
///     │ └─┘└───────┘ └──────────────────────────┘ └───────┘└─┘ │
///     └──────────────────────────────────────────────────────────┘
///
/// The case is drawn tone on tone in one neutral, as those wallpapers are drawn in one
/// hue, and the bento's parts keep their own dark finish, so the colour on it is the
/// data: the cores lit by their load, the memory and the drive filled by how full they
/// are, the cells by their charge. Every reading sits in clear space beside its part,
/// or on the part where the bento prints it, as it prints what is free on the memory
/// and the drive. Pointing at a part opens its detail beside the panel, as a bento card
/// does. Built from shapes, never a `Canvas`: see `PlotShape` for why.
struct MacBookView: View {
    let engine: MetricsEngine
    let settings: SettingsStore
    let layout: PanelLayoutState?

    private static let size = CGSize(width: 706, height: 520)
    private static let inset: CGFloat = 14
    static let width = size.width + inset * 2

    // Where everything sits, in the machine's own points, mirrored about the middle.
    private static let leftHinge = CGRect(x: 40, y: 16, width: 96, height: 14)
    private static let rightHinge = CGRect(x: 570, y: 16, width: 96, height: 14)
    private static let vent = CGRect(x: 148, y: 17, width: 410, height: 12)
    /// The fin stack above, the housing below it. Down to the board in the App Store's
    /// copy, which has no fan speeds to show under them.
    private static let fanHeight: CGFloat = Capabilities.readsSensors ? 158 : 208
    private static let leftFan = CGRect(x: 26, y: 40, width: 140, height: fanHeight)
    private static let rightFan = CGRect(x: 540, y: 40, width: 140, height: fanHeight)
    /// The logic board: a column up the middle between the fans, and a band right across
    /// under them.
    private static let boardColumn = CGRect(x: 178, y: 40, width: 350, height: 302)
    private static let boardBand = CGRect(x: 12, y: 260, width: 682, height: 82)
    /// The bento's parts at the sizes their cards draw them, and where they sit here.
    private static let chipNative = CGSize(width: 140, height: 140)
    private static let gpuNative = CGSize(width: 200, height: 106)
    private static let memoryNative = CGSize(width: 200, height: 56)
    private static let ssdNative = CGSize(width: 200, height: 44)
    private static let cpu = CGRect(x: 192, y: 66, width: 124, height: 124)
    private static let gpu = CGRect(x: 334, y: 80.3, width: 180, height: 95.4)
    /// The module and the drive at one scale, centred on one line.
    private static let memory = CGRect(x: 20, y: 288, width: 152, height: 42.56)
    private static let ssd = CGRect(x: 534, y: 292.56, width: 152, height: 33.44)
    private static let leftSpeaker = CGRect(x: 20, y: 354, width: 28, height: 150)
    private static let leftCells = CGRect(x: 58, y: 354, width: 168, height: 150)
    private static let trackpad = CGRect(x: 238, y: 354, width: 230, height: 150)
    private static let rightCells = CGRect(x: 480, y: 354, width: 168, height: 150)
    private static let rightSpeaker = CGRect(x: 658, y: 354, width: 28, height: 150)
    /// Where the readings under the fans start.
    private static let readingsTop: CGFloat = 206
    /// How far the CPU's and the GPU's readings sit under their chips: as far as the
    /// fans' readings sit under the fans.
    private static let chipGap: CGFloat = 8
    /// Where the labels over the band's parts start.
    private static let labelsTop: CGFloat = 270

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

    private var fans: some View {
        let fans = engine.thermal.value?.fans ?? []
        return canvas {
            place(fan(fans.first, isMirrored: false).hoverRegion(.thermal, layout: layout), Self.leftFan)
            place(fan(fans.count > 1 ? fans[1] : fans.first, isMirrored: true)
                .hoverRegion(.thermal, layout: layout), Self.rightFan)
        }
    }

    /// The fin stack the fan blows through, and the fan in its housing: square where it
    /// meets the fins, round where it wraps the blades.
    private func fan(_ fan: FanInfo?, isMirrored: Bool) -> some View {
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
        let outline = BoardOutline(column: Self.boardColumn, band: Self.boardBand, radius: 12)
        return canvas {
            outline.fill(LinearGradient(colors: [Tone.boardTop, Tone.board], startPoint: .top, endPoint: .bottom))
            outline.stroke(Tone.edge, lineWidth: 1)
            BoardParts(kind: .capacitors).fill(Tone.component)
            BoardParts(kind: .chips).fill(Tone.boardChip)
            BoardParts(kind: .chips).stroke(Color.white.opacity(0.14), lineWidth: 0.75)
            ForEach(Array(Self.boardScrews.enumerated()), id: \.offset) { _, point in
                screw.position(point)
            }
        }
    }

    private static let boardScrews = [CGPoint(x: 353, y: 50), CGPoint(x: 196, y: 334), CGPoint(x: 510, y: 334)]

    /// Copper, from along the foot of the fins at each fan's outlet, over the top of the
    /// board and down under the CPU on the left and the GPU on the right, which cover
    /// their ends.
    private var heatPipes: some View {
        let pipes = [HeatPipe(from: CGPoint(x: 46, y: 55), along: 226, to: CGPoint(x: 246, y: 90)),
                     HeatPipe(from: CGPoint(x: 660, y: 55), along: 486, to: CGPoint(x: 466, y: 104))]
        return canvas {
            ForEach(pipes.indices, id: \.self) { index in
                pipes[index].stroke(Color.black.opacity(0.18),
                                    style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                    .offset(y: 1)
                pipes[index].stroke(Copper.pipe, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                pipes[index].stroke(Copper.shine.opacity(0.8),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .offset(y: -2)
            }
        }
    }

    // MARK: Chips

    /// The bento's CPU chip, its cores lit by their load, and its GPU, its cores switching
    /// on as the load rises, side by side where the heat pipes end.
    private var chips: some View {
        let cpu = engine.cpu.value
        let kinds = cpu?.coreKinds ?? []
        let loads = cpu?.perCore.map(\.busy) ?? []
        // A core the system did not classify is drawn as a performance core: that is what
        // a chip without the split has.
        let performance = loads.indices.filter { $0 >= kinds.count || kinds[$0] != .efficiency }.map { loads[$0] }
        let efficiency = loads.indices.filter { $0 < kinds.count && kinds[$0] == .efficiency }.map { loads[$0] }
        let device = engine.gpu.value?.primary
        return canvas {
            place(scaled(ChipGraphic(name: engine.system.value?.chipName,
                                     performance: performance, efficiency: efficiency,
                                     performanceColors: [.white, .white],
                                     efficiencyColors: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)]),
                         native: Self.chipNative, width: Self.cpu.width)
                .shadow(color: Tone.dropShadow, radius: 3, y: 1)
                .hoverRegion(.cpu, layout: layout), Self.cpu)
            place(gpuDie(cores: device?.coreCount ?? engine.system.value?.gpuCoreCount ?? 0,
                         load: device?.utilization ?? 0)
                .shadow(color: Tone.dropShadow, radius: 3, y: 1)
                .hoverRegion(.gpu, layout: layout), Self.gpu)
        }
    }

    @ViewBuilder
    private func gpuDie(cores: Int, load: Double) -> some View {
        if cores > 0 {
            scaled(GPUDie(cores: cores, load: load, colors: palette(.gpu), size: Self.gpuNative),
                   native: Self.gpuNative, width: Self.gpu.width)
        } else {
            // No core count to lay the cores out by: the package and its name alone.
            ZStack {
                ChipFace()
                Text("GPU")
                    .font(.system(size: 29, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(ChipGraphic.silver)
            }
            .padding(4)
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

    /// Each part's reading in the clear space beside it: under the fans and the chips,
    /// and over the band's parts the way a bento card's header sits over its object.
    private var readings: some View {
        let thermal = engine.thermal.value
        let fans = thermal?.fans ?? []
        let cpu = engine.cpu.value
        let gpu = engine.gpu.value?.primary
        let memory = engine.memory.value
        let root = engine.disk.value?.rootVolume
        return canvas {
            fanReading(fans.first).hoverRegion(.thermal, layout: layout)
                .top(at: CGPoint(x: Self.leftFan.midX, y: Self.readingsTop))
            if fans.count > 1 {
                fanReading(fans[1]).hoverRegion(.thermal, layout: layout)
                    .top(at: CGPoint(x: Self.rightFan.midX, y: Self.readingsTop))
            }
            reading("CPU", cpu.map { formatter.percent($0.total.busy) }, colors: palette(.cpu),
                    celsius: thermal?.cpuCelsius)
                .hoverRegion(.cpu, layout: layout)
                .top(at: CGPoint(x: Self.cpu.midX, y: Self.cpu.maxY + Self.chipGap))
            reading("GPU", gpu?.utilization.map { formatter.percent($0) }, colors: palette(.gpu),
                    celsius: thermal?.gpuCelsius)
                .hoverRegion(.gpu, layout: layout)
                .top(at: CGPoint(x: Self.gpu.midX, y: Self.gpu.maxY + Self.chipGap))
            label("Memory", memory.map { formatter.memory($0.totalBytes) })
                .hoverRegion(.memory, layout: layout)
                .top(at: CGPoint(x: Self.memory.midX, y: Self.labelsTop))
            network.hoverRegion(.network, layout: layout)
                .top(at: CGPoint(x: Self.boardColumn.midX, y: Self.labelsTop))
            label("SSD", root.map { formatter.storage($0.totalBytes) }, celsius: Self.hottest(thermal, .storage))
                .hoverRegion(.disk, layout: layout)
                .top(at: CGPoint(x: Self.ssd.midX, y: Self.labelsTop))
        }
    }

    /// How fast a fan is going. Nothing under a fan the App Store's copy cannot read: its
    /// blades are the drawing's, not a reading.
    @ViewBuilder
    private func fanReading(_ fan: FanInfo?) -> some View {
        if let fan {
            reading(fan.name, fan.currentRPM < 1 ? "Off" : formatter.percent(fan.speedFraction),
                    colors: Self.fanColors, detail: fan.currentRPM < 1 ? nil : formatter.rpm(fan.currentRPM))
        } else if Capabilities.readsSensors {
            reading("Fans", "None", colors: [Design.Palette.secondaryText])
        }
    }

    /// The network's name over the Wi-Fi module under its shield, and beside the module
    /// what is going up and coming down, as the bento's network card sets them.
    private var network: some View {
        let network = engine.network.value ?? engine.lastKnown.network.value
        let can = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return VStack(spacing: 6) {
            caption(network?.wifi?.ssid ?? (network?.wifi != nil || network == nil ? "Wi-Fi" : "Network"))
                .frame(maxWidth: 150)
            HStack(spacing: 10) {
                ZStack {
                    can.fill(LinearGradient(colors: [Tone.shieldTop, Tone.shield],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    DotGrid(pitch: 5, radius: 0.7).fill(Tone.well.opacity(0.7)).padding(5).clipShape(can)
                    Image(systemName: network?.wifi != nil || network == nil ? "wifi" : "network")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(gradient(palette(.network)))
                    can.strokeBorder(Tone.edge, lineWidth: 1)
                }
                .frame(width: 38, height: 38)
                .shadow(color: Tone.dropShadow, radius: 2, y: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("↑ " + (network.map { formatter.networkRate($0.uploadBytesPerSecond) } ?? MetricFormatter.unavailable))
                        .foregroundStyle(gradient(Self.upColors))
                    Text("↓ " + (network.map { formatter.networkRate($0.downloadBytesPerSecond) } ?? MetricFormatter.unavailable))
                        .foregroundStyle(gradient(Self.downColors))
                }
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// A part's reading: what it is in small capitals, the figure in the part's colours,
    /// and under it the part's temperature where it has a sensor, or a detail.
    private func reading(_ title: String, _ value: String?, colors: [Color], size: CGFloat = 16,
                         celsius: Double? = nil, detail: String? = nil) -> some View {
        VStack(spacing: 1) {
            caption(title)
            Text(value ?? MetricFormatter.unavailable)
                .font(.system(size: size, weight: .bold).monospacedDigit())
                .foregroundStyle(gradient(colors))
                .contentTransition(.numericText())
            if let celsius {
                temperature(celsius)
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Design.Palette.secondaryText)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// A part's name in small capitals and what it holds beside it, over a part that
    /// carries its own reading, as a bento card's header names its object.
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

    /// What holds a part down.
    private var screw: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Tone.screwTop, Tone.screw], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(Tone.edge, lineWidth: 0.75)
            Circle().fill(Tone.well).frame(width: 3.5, height: 3.5)
        }
        .frame(width: 9, height: 9)
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
        static let boardTop = shade(0.165)
        static let board = shade(0.14)
        static let partTop = shade(0.235)
        static let part = shade(0.195)
        static let well = shade(0.11)
        static let shieldTop = shade(0.42)
        static let shield = shade(0.27)
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

/// A heat pipe: straight along from the fins to `along`, then curving down into the chip.
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

/// The logic board's outline: a column up the middle and a band across its foot, as one
/// path so its edge runs round the corners where the two meet.
private struct BoardOutline: Shape {
    let column: CGRect
    /// Sharing the column's foot.
    let band: CGRect
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let corners = [CGPoint(x: column.minX, y: column.minY), CGPoint(x: column.maxX, y: column.minY),
                       CGPoint(x: column.maxX, y: band.minY), CGPoint(x: band.maxX, y: band.minY),
                       CGPoint(x: band.maxX, y: band.maxY), CGPoint(x: band.minX, y: band.maxY),
                       CGPoint(x: band.minX, y: band.minY), CGPoint(x: column.minX, y: band.minY)]
        var path = Path()
        path.move(to: CGPoint(x: column.midX, y: column.minY))
        for index in corners.indices {
            path.addArc(tangent1End: corners[(index + 1) % corners.count],
                        tangent2End: corners[(index + 2) % corners.count], radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

/// The small parts around a logic board's big ones, at fixed places so the board looks
/// the same every time it is drawn: a column of capacitors between the CPU and the GPU,
/// and either side of the Wi-Fi module the power controllers with capacitors beside them.
private struct BoardParts: Shape {
    enum Kind { case chips, capacitors }

    let kind: Kind

    /// In the machine's points, the band's left half; the right half mirrors it.
    private static let chips = [CGRect(x: 188, y: 280, width: 26, height: 26),
                                CGRect(x: 222, y: 284, width: 16, height: 11),
                                CGRect(x: 188, y: 314, width: 16, height: 12)]
    private static let width: CGFloat = 706

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func add(_ part: CGRect, radius: CGFloat, mirrored: Bool = true) {
            let mirror = CGRect(x: Self.width - part.maxX, y: part.minY, width: part.width, height: part.height)
            for frame in mirrored ? [part, mirror] : [part] {
                path.addRoundedRect(in: frame, cornerSize: CGSize(width: radius, height: radius))
            }
        }
        guard kind == .capacitors else {
            for chip in Self.chips { add(chip, radius: 1.5) }
            return path
        }
        for y in stride(from: CGFloat(78), through: 178, by: 9) {
            add(CGRect(x: 323, y: y, width: 4, height: 2.5), radius: 0.5, mirrored: false)
        }
        for x in stride(from: CGFloat(222), through: 250, by: 7) {
            add(CGRect(x: x, y: 304, width: 2.5, height: 4), radius: 0.5)
            add(CGRect(x: x, y: 312, width: 2.5, height: 4), radius: 0.5)
        }
        for y in stride(from: CGFloat(278), through: 324, by: 9) {
            add(CGRect(x: 262, y: y, width: 4, height: 2.5), radius: 0.5)
        }
        return path
    }
}
/// Holes in rows, each row half a pitch along from the last: a speaker's grille, or the
/// vents in a shield.
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
