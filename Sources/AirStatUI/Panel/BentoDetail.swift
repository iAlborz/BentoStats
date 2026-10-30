import SwiftUI
import AppKit
import AirStatKit

/// What hovering a bento card opens beside the panel: what the card has no room for,
/// and nothing it already shows.
///
/// Drawn the way the panel is: tiles on the panel's backdrop, each a big reading in the
/// card's colour over a short caption, and the module's history last. The card answers
/// "how is it now"; the detail answers "and what else", so no figure appears in both.
///
/// Temperatures are thermometers wherever they appear, red as the card's is. A part's
/// temperature sits with the part: the GPU's with the GPU, the battery's with
/// the battery, the SSD's with the SSD. The Temperature card is the CPU's, so its detail
/// carries the CPU's hottest sensor, the enclosure and the fans.
struct BentoDetail: View {
    let module: PanelModule
    let engine: MetricsEngine
    let settings: SettingsStore

    static let inset: CGFloat = 12
    private static let gap: CGFloat = 10
    /// Three of the panel's cells across, so the tiles keep the cards' rhythm.
    static let width: CGFloat = inset * 2 + 110 * 3 + gap * 2

    /// Which window the history shows, once the user has picked one.
    @State private var historyRange: HistoryRange?

    private var formatter: MetricFormatter {
        MetricFormatter(settings: settings.settings.general)
    }

    private var palette: [Color] {
        BentoGrid.palette(module)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            header
            content
        }
        .padding(Self.inset)
        .frame(width: Self.width, alignment: .topLeading)
        .environment(\.metricFormatter, formatter)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Design.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(gradient(palette))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Design.Palette.primaryText)
            Spacer(minLength: 0)
            if module == .network, engine.network.value?.isVPNActive == true {
                Text("VPN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Design.Palette.secondaryText)
                    .padding(.horizontal, Design.Space.s)
                    .padding(.vertical, Design.Space.xxs)
                    .background(Capsule().fill(Design.Palette.track))
            }
        }
        .padding(.horizontal, Design.Space.xs)
    }

    /// The card's own name for the thing, where the card shows one.
    private var title: String {
        switch module {
        case .disk: return String(localized: "SSD")
        case .network:
            guard let network = engine.network.value else { return module.label }
            return network.wifi != nil ? String(localized: "Wi-Fi") : network.connectionType.label
        case .battery: return engine.power.value?.hasBattery == false ? String(localized: "Power") : module.label
        default: return module.label
        }
    }

    private var symbol: String {
        guard module == .network, let network = engine.network.value else { return module.symbolName }
        return network.wifi != nil ? "wifi" : "network"
    }

    // MARK: Modules

    @ViewBuilder
    private var content: some View {
        switch module {
        case .cpu: section(engine.cpu) { cpu($0) }
        case .memory: section(engine.memory) { memory($0) }
        case .gpu: section(engine.gpu) { gpu($0) }
        case .disk: section(engine.disk) { disk($0) }
        case .battery: section(engine.power) { battery($0) }
        case .network: section(engine.network) { network($0) }
        case .thermal: section(engine.thermal) { thermal($0) }
        case .system: section(engine.system) { system($0) }
        case .processes: EmptyView()
        }
    }

    /// The card shows the chip's cores and the busiest processes. This is the load in
    /// figures: overall, per cluster, user against system, and the queue behind it.
    @ViewBuilder
    private func cpu(_ cpu: CPUSnapshot) -> some View {
        stats(clusters(cpu))
        stats([Stat(formatter.percent(cpu.total.user), String(localized: "User")),
               Stat(formatter.percent(cpu.total.system), String(localized: "System")),
               Stat(formatter.count(cpu.threadCount), String(localized: "Threads"))])
        tile(caption: String(localized: "Load average")) {
            HStack(spacing: 0) {
                loadAverage(cpu.loadAverage.one, String(localized: "1 min"))
                loadAverage(cpu.loadAverage.five, String(localized: "5 min"))
                loadAverage(cpu.loadAverage.fifteen, String(localized: "15 min"))
            }
        }
        history()
    }

    private func clusters(_ cpu: CPUSnapshot) -> [Stat] {
        let performance = cpu.coreKinds.filter { $0 == .performance }.count
        let efficiency = cpu.coreKinds.filter { $0 == .efficiency }.count
        var clusters = [Stat(formatter.percent(cpu.total.busy), String(localized: "Usage"))]
        if let busy = cpu.performanceBusy, performance > 0 {
            clusters.append(Stat(formatter.percent(busy), String(localized: "\(performance) P-cores")))
        }
        if let busy = cpu.efficiencyBusy, efficiency > 0 {
            // Green, as the chip draws its efficiency cores.
            clusters.append(Stat(formatter.percent(busy), String(localized: "\(efficiency) E-cores"),
                                 colors: [Color(nsColor: .systemGreen), Color(nsColor: .systemMint)]))
        }
        return clusters
    }

    private func loadAverage(_ load: Double, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(formatter.fixed(load, decimals: 2))
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundStyle(gradient(palette))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Design.Palette.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    /// The card shows used against free and the biggest users. This is whether that is
    /// a problem, pressure and swap, and what the used part is made of.
    @ViewBuilder
    private func memory(_ memory: MemorySnapshot) -> some View {
        let swap = memory.swapTotalBytes > 0 ? String(localized: "Swap of \(formatter.memory(memory.swapTotalBytes))") : String(localized: "Swap used")
        stats([Stat(memory.memoryPressure.label,
                    String(localized: "Pressure · \(formatter.percent(memory.pressureFraction))"),
                    fraction: memory.pressureFraction,
                    colors: BentoGrid.pressureColors(memory.memoryPressure)),
               Stat(formatter.memory(memory.swapUsedBytes), swap)])
        tile(caption: String(localized: "What's in memory")) { composition(memory) }
        history()
    }

    /// The card shows the load, the GPU's memory and its two engines, so all that is
    /// left is how hot it runs and how busy it has been.
    @ViewBuilder
    private func gpu(_ gpu: GPUSnapshot) -> some View {
        stats(gpuTemperatures())
        history(available: gpu.primary?.utilization != nil)
    }

    private func gpuTemperatures() -> [Stat] {
        guard let thermal = engine.thermal.value, let celsius = thermal.gpuCelsius else { return [] }
        var items = [temperature(celsius, String(localized: "Temperature"))]
        if let hottest = Self.hottest(thermal, .gpu, ifMoreThanOne: true) {
            items.append(temperature(hottest, String(localized: "Hotspot")))
        }
        return items
    }

    /// The card shows free space and the transfer rates now. This is the totals since
    /// boot, who is doing the reading and writing, and any other drive attached.
    @ViewBuilder
    private func disk(_ disk: DiskSnapshot) -> some View {
        stats(diskTotals(disk))
        tile(caption: String(localized: "Reading and writing now")) {
            let busiest = diskBusiest()
            if busiest.isEmpty {
                placeholder(String(localized: "Nothing is using the disk"))
            } else {
                processRows(busiest)
            }
        }
        let others = disk.volumes.filter { !$0.isRoot }
        if !others.isEmpty {
            tile(caption: others.count == 1 ? String(localized: "Other volume") : String(localized: "Other volumes")) {
                VStack(spacing: Design.Space.m) {
                    ForEach(others) { volumeRow($0) }
                }
            }
        }
        history()
    }

    private func diskTotals(_ disk: DiskSnapshot) -> [Stat] {
        var totals = [Stat(formatter.storage(disk.totalReadBytes), String(localized: "Read since boot")),
                      Stat(formatter.storage(disk.totalWriteBytes), String(localized: "Written since boot"))]
        if let thermal = engine.thermal.value, let celsius = Self.hottest(thermal, .storage) {
            totals.append(temperature(celsius, String(localized: "Temperature")))
        }
        return totals
    }

    /// The processes moving the most data, of those the process sample holds.
    private func diskBusiest() -> [(ProcessRow, String)] {
        guard let processes = engine.processes.value else { return [] }
        let rated = processes.processes.map { process -> (ProcessRow, Double) in
            (process, (process.diskReadBytesPerSecond ?? 0) + (process.diskWriteBytesPerSecond ?? 0))
        }
        let busiest = rated.filter { $0.1 >= 1 }.sorted { $0.1 > $1.1 }.prefix(4)
        return busiest.map { ($0.0, formatter.diskRate($0.1)) }
    }

    /// The card shows the charge and the time left. This is the battery's condition,
    /// what it is drawing, what it is plugged into, and the other devices' batteries.
    @ViewBuilder
    private func battery(_ power: PowerSnapshot) -> some View {
        stats(powerStats(power))
        if !power.accessories.isEmpty {
            tile(caption: String(localized: "Devices")) {
                VStack(spacing: Design.Space.s) {
                    ForEach(power.accessories) { accessoryRow($0) }
                }
            }
        }
        history(available: power.hasBattery && power.percentage != nil)
    }

    private func powerStats(_ power: PowerSnapshot) -> [Stat] {
        var items: [Stat] = []
        if power.hasBattery {
            if let health = power.healthPercent {
                items.append(Stat(formatter.percentValue(health), String(localized: "Health"), fraction: health / 100))
            }
            if let cycles = power.cycleCount {
                items.append(Stat(formatter.count(cycles), String(localized: "Cycles")))
            }
            if let condition = power.condition {
                items.append(Stat(condition, String(localized: "Condition")))
            }
            if let watts = power.batteryWatts, abs(watts) >= 0.1 {
                items.append(Stat(formatter.watts(abs(watts)), power.isCharging ? String(localized: "Charging at") : String(localized: "Drawing")))
            }
            if let celsius = power.temperatureCelsius
                ?? engine.thermal.value.flatMap({ Self.hottest($0, .battery) }) {
                items.append(temperature(celsius, String(localized: "Temperature")))
            }
        }
        if let watts = power.adapterWatts {
            items.append(Stat("\(formatter.count(watts)) W", String(localized: "Adapter")))
        } else if power.isPluggedIn, let name = power.adapterName {
            items.append(Stat(name, String(localized: "Adapter"), size: 15))
        }
        if power.isLowPowerMode {
            items.append(Stat(String(localized: "On"), String(localized: "Low Power Mode")))
        }
        if power.isOptimizedChargingPaused {
            items.append(Stat(String(localized: "On hold"), String(localized: "Optimized charging")))
        }
        return items
    }

    /// The card shows the rates now and the network's name. This is the link itself,
    /// the addresses, and how much has moved since boot.
    @ViewBuilder
    private func network(_ network: NetworkSnapshot) -> some View {
        stats(link(network.wifi))
        stats(addresses(network))
        // In the card's colours for the two directions: blue coming in, red going out.
        stats([Stat(formatter.storage(network.totalDownloadBytes), String(localized: "Downloaded since boot"),
                    colors: [Color(nsColor: .systemBlue), Color(nsColor: .systemCyan)]),
               Stat(formatter.storage(network.totalUploadBytes), String(localized: "Uploaded since boot"),
                    colors: [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)])])
        history()
    }

    private func link(_ wifi: WiFiInfo?) -> [Stat] {
        guard let wifi else { return [] }
        var link: [Stat] = []
        if let rssi = wifi.rssi {
            link.append(Stat("\(rssi) dBm", String(localized: "Signal"), fraction: wifi.signalQuality))
        }
        if let rate = wifi.transmitRateMbps {
            link.append(Stat("\(formatter.fixed(rate, decimals: 0)) Mbps", String(localized: "Link rate")))
        }
        if let channel = wifi.channel {
            link.append(Stat("\(channel)", wifi.band.map { String(localized: "Channel · \($0)") } ?? String(localized: "Channel")))
        }
        return link
    }

    private func addresses(_ network: NetworkSnapshot) -> [Stat] {
        var addresses: [Stat] = []
        if let local = network.localIPv4 {
            addresses.append(Stat(local, String(localized: "Local IP"), size: 16))
        }
        if let publicIP = publicIP(network.publicIP) {
            addresses.append(Stat(publicIP, String(localized: "Public IP"), size: 16))
        }
        return addresses
    }

    /// The card shows the CPU's average and the thermal state. This is its hottest
    /// sensor, the enclosure, and the fans that answer them.
    @ViewBuilder
    private func thermal(_ thermal: ThermalSnapshot) -> some View {
        // Fans are read out with where they sit between idle and flat out: a stopped fan
        // is normal on a Mac that is not working hard, and "0 RPM" says so.
        stats(thermal.fans.map {
            Stat(formatter.rpm($0.currentRPM), $0.name, fraction: $0.loadFraction,
                 colors: [Color(nsColor: .systemCyan), Color(nsColor: .systemBlue)])
        })
        stats(sensors(thermal))
        if let reason = thermal.sensorsUnavailableReason {
            tile { UnavailableNote(.unsupported(reason)).frame(maxWidth: .infinity, alignment: .leading) }
        }
        history(available: thermal.cpuCelsius != nil)
    }

    private func sensors(_ thermal: ThermalSnapshot) -> [Stat] {
        var sensors: [Stat] = []
        if let hottest = Self.hottest(thermal, .cpu, ifMoreThanOne: true) {
            sensors.append(temperature(hottest, String(localized: "CPU hotspot")))
        }
        if let enclosure = Self.hottest(thermal, .ambient) {
            sensors.append(temperature(enclosure, String(localized: "Enclosure")))
        }
        return sensors
    }

    /// The card shows the uptime, exactly which Mac it is, and the macOS version. This is
    /// the rest of what identifies it: its names and the build it runs.
    @ViewBuilder
    private func system(_ system: SystemInfoSnapshot) -> some View {
        stats([Stat(system.computerName, String(localized: "Computer name"), size: 16)].filter { !$0.value.isEmpty })
        stats([Stat(system.osBuild, String(localized: "\(system.osName) build"), size: 16),
               Stat(system.hostName, String(localized: "Host name"), size: 16)])
    }

    // MARK: Pieces

    /// One reading for a tile: a big value over a caption, with a slim bar under the
    /// value when it has a range to sit in.
    private struct Stat {
        var value: String
        var caption: String
        var fraction: Double?
        var colors: [Color]?
        var size: CGFloat
        /// A temperature, drawn with a thermometer beside the value.
        var celsius: Double?

        init(_ value: String, _ caption: String, fraction: Double? = nil,
             colors: [Color]? = nil, size: CGFloat = 20, celsius: Double? = nil) {
            self.value = value
            self.caption = caption
            self.fraction = fraction
            self.colors = colors
            self.size = size
            self.celsius = celsius
        }
    }

    /// A temperature as a thermometer and its reading, red as the card's thermometer is.
    private func temperature(_ celsius: Double, _ caption: String) -> Stat {
        Stat(formatter.temperature(celsius), caption, colors: Self.heat, celsius: celsius)
    }

    /// Readings as tiles, three across, or two across for two or four of them.
    @ViewBuilder
    private func stats(_ items: [Stat]) -> some View {
        let columns = items.count == 2 || items.count == 4 ? 2 : 3
        let rows = stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
        ForEach(rows.indices, id: \.self) { row in
            HStack(spacing: Self.gap) {
                ForEach(rows[row].indices, id: \.self) { index in
                    statTile(rows[row][index])
                }
            }
        }
    }

    private func statTile(_ stat: Stat) -> some View {
        let colors = stat.colors ?? palette
        return HStack(spacing: Design.Space.m) {
            if let celsius = stat.celsius {
                // The card's scale: 30°C empty, 100°C full.
                ThermometerGraphic(fraction: min(max((celsius - 30) / 70, 0), 1),
                                   colors: colors, scale: 0.5)
                    .frame(width: 14, height: 50)
                    .padding(.trailing, Design.Space.xxs)
            }
            reading(stat, colors: colors)
        }
        .padding(.horizontal, Design.Space.m)
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background(surface)
        .accessibilityElement(children: .combine)
    }

    private func reading(_ stat: Stat, colors: [Color]) -> some View {
        VStack(spacing: Design.Space.xs) {
            Text(stat.value)
                .font(.system(size: stat.size, weight: .bold).monospacedDigit())
                .foregroundStyle(gradient(colors))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            if let fraction = stat.fraction {
                ZStack(alignment: .leading) {
                    Capsule().fill(Design.Palette.track)
                    Capsule().fill(gradient(colors))
                        .frame(width: 56 * min(max(fraction, 0), 1))
                }
                .frame(width: 56, height: 4)
            }
            Text(stat.caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Design.Palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// A tile for anything that is not one reading, its caption under it as on the cards.
    private func tile<Content: View>(caption: String? = nil,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Design.Space.m) {
            content()
            if let caption {
                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Design.Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(Design.Space.l)
        .frame(maxWidth: .infinity)
        .background(surface)
    }

    private var surface: some View {
        RoundedRectangle(cornerRadius: Design.Radius.tile, style: .continuous).fill(BentoGrid.surface)
    }

    /// The module's history in its own colour, where it has one and charts are on.
    @ViewBuilder
    private func history(available: Bool = true) -> some View {
        if available, settings.settings.panel.showsHistoryChart, let series = module.historySeries {
            tile {
                HistoryChart(series,
                             history: engine.history,
                             day: engine.dayHistory,
                             settings: settings.settings.charts,
                             tint: palette[0],
                             band: palette[0].opacity(0.14),
                             range: $historyRange)
            }
        }
    }

    /// A spinner while the module waits for its first reading, the reason when it has none.
    @ViewBuilder
    private func section<Value: Sendable & Equatable, Content: View>(
        _ state: MetricState<Value>,
        @ViewBuilder _ content: (Value) -> Content
    ) -> some View {
        switch state {
        case .value(let value):
            content(value)
        case .failure(.pending):
            tile { ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 44) }
        case .failure(let failure):
            tile { UnavailableNote(failure).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }

    /// "App 13 GB, Wired 4.0 GB…" as one bar across all of memory, the way Activity
    /// Monitor splits it, in steps of the card's colour. Cached files are the palest:
    /// macOS hands them back the moment anything asks, which is why the card counts them
    /// as free.
    private func composition(_ memory: MemorySnapshot) -> some View {
        let color = palette[0]
        let parts: [(name: String, bytes: UInt64, shade: Double)] = [
            (String(localized: "App"), memory.appBytes, 1), (String(localized: "Wired"), memory.wiredBytes, 0.7),
            (String(localized: "Compressed"), memory.compressedBytes, 0.45), (String(localized: "Cached"), memory.cachedBytes, 0.22),
        ]
        let total = Double(max(memory.totalBytes, 1))
        return VStack(spacing: Design.Space.m) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.name) { part in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color.opacity(part.shade))
                            .frame(width: max(0, geometry.size.width * Double(part.bytes) / total - 2))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 14)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Design.Palette.track))
            Grid(horizontalSpacing: Design.Space.xl, verticalSpacing: Design.Space.xs) {
                ForEach([0, 2], id: \.self) { start in
                    GridRow {
                        ForEach(parts[start..<start + 2], id: \.name) { part in
                            HStack(spacing: Design.Space.s) {
                                Circle().fill(color.opacity(part.shade)).frame(width: 7, height: 7)
                                Text(part.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Design.Palette.secondaryText)
                                Spacer(minLength: Design.Space.s)
                                Text(formatter.memory(part.bytes))
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Design.Palette.primaryText)
                            }
                        }
                    }
                }
            }
        }
    }

    private func processRows(_ rows: [(ProcessRow, String)]) -> some View {
        VStack(spacing: 3) {
            ForEach(rows, id: \.0.pid) { process, value in
                HStack(spacing: Design.Space.s) {
                    ProcessIcon(process: process, size: 14)
                    Text(process.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Design.Palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: Design.Space.s)
                    Text(value)
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Design.Palette.secondaryText)
                }
                .frame(height: 16)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Design.Palette.tertiaryText)
            .frame(maxWidth: .infinity, minHeight: 16)
    }

    /// Another drive: its name, how full it is, and what is left of what.
    private func volumeRow(_ volume: VolumeInfo) -> some View {
        let used = volume.totalBytes > 0 ? 1 - Double(volume.availableBytes) / Double(volume.totalBytes) : 0
        return VStack(spacing: Design.Space.xs) {
            HStack(spacing: Design.Space.xs) {
                Text(volume.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Design.Palette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if volume.isEjectable {
                    Image(systemName: "eject.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Design.Palette.tertiaryText)
                }
                Spacer(minLength: Design.Space.s)
                Text("\(formatter.storage(volume.availableBytes)) free of \(formatter.storage(volume.totalBytes))")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Design.Palette.secondaryText)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Design.Palette.track)
                    Capsule().fill(gradient(palette)).frame(width: geometry.size.width * used)
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }

    private func accessoryRow(_ accessory: AccessoryBattery) -> some View {
        HStack(spacing: Design.Space.m) {
            BatteryGraphic(fraction: accessory.percent / 100, isCharging: accessory.isCharging,
                           charge: palette[0], scale: 0.32)
                .frame(width: 28, height: 13)
            Text(accessory.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Design.Palette.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Design.Space.s)
            Text(accessoryValue(accessory))
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Design.Palette.secondaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// "64%", or for earbuds each part in turn, "L 64%  R 71%  Case 90%": one flat bud
    /// is the one that gets swapped into the case.
    private func accessoryValue(_ accessory: AccessoryBattery) -> String {
        guard !accessory.parts.isEmpty else { return formatter.percentValue(accessory.percent) }
        return accessory.parts.map { part in
            let label = switch part.name.lowercased() {
            case "left": "L"
            case "right": "R"
            default: part.name
            }
            return "\(label) \(formatter.percentValue(part.percent))"
        }.joined(separator: "  ")
    }

    /// The address, a lookup in flight, or nothing at all while the lookup is switched off.
    private func publicIP(_ state: MetricState<String>) -> String? {
        switch state {
        case .value(let address): return address
        case .failure(.unsupported): return nil
        case .failure(.pending): return String(localized: "Looking up…")
        case .failure: return MetricFormatter.unavailable
        }
    }

    /// The hottest sensor of a kind, or nil when there is none. With `ifMoreThanOne`, nil
    /// as well when there is only one: then the hottest is the average already shown.
    private static func hottest(_ thermal: ThermalSnapshot, _ category: SensorCategory,
                                ifMoreThanOne: Bool = false) -> Double? {
        let readings = thermal.sensors.filter { $0.category == category }.map(\.celsius)
        guard readings.count > (ifMoreThanOne ? 1 : 0) else { return nil }
        return readings.max()
    }

    private static let heat = [Color(nsColor: .systemRed), Color(nsColor: .systemOrange)]

    private func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
