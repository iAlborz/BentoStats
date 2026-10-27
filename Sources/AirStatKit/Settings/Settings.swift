import Foundation

// MARK: - Lenient decoding

/// Decode a key, falling back to a default when it is missing *or malformed*.
///
/// Settings files get hand-edited, truncated by power loss, and written by older
/// builds. A single bad key must never cost the user their whole configuration,
/// so every property in this file decodes through here.
extension KeyedDecodingContainer {
    /// `try?` flattens the `T??` here, so a key that is absent and a key that fails
    /// to decode both land on `fallback` — which is exactly the desired behaviour.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        guard let decoded = try? decodeIfPresent(T.self, forKey: key) else { return fallback }
        return decoded
    }
}

// MARK: - Units and formatting

public enum TemperatureUnit: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case celsius, fahrenheit

    public var label: String {
        switch self {
        case .celsius: return "Celsius (°C)"
        case .fahrenheit: return "Fahrenheit (°F)"
        }
    }
    public var suffix: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}

/// Network rates are conventionally quoted in bits (Mbps) by ISPs and bytes (MB/s)
/// by file transfer UI. Both are offered because both are "correct".
public enum NetworkRateUnit: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case bytes, bits

    public var label: String {
        switch self {
        case .bytes: return "Bytes per second (MB/s)"
        case .bits: return "Bits per second (Mbps)"
        }
    }
}

/// GiB (1024-based, what Activity Monitor's graphs use) vs GB (1000-based, what
/// Finder and Apple's marketing use).
/// Applies to STORAGE only. Physical memory is always formatted in binary units
/// because that is what Apple itself does (18 GB of RAM is 19,327,352,832 bytes).
public enum ByteUnitStyle: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case binary, decimal

    public var label: String {
        switch self {
        case .binary: return "Binary (1 GB = 1024 MB)"
        case .decimal: return "Decimal (1 GB = 1000 MB)"
        }
    }
    public var base: Double { self == .binary ? 1024 : 1000 }
}

public enum AppearanceMode: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case system, light, dark

    public var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - Menu bar

/// A single readout the user can place in the menu bar.
public enum MenuBarMetric: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case cpuUsage, cpuTemperature, cpuFrequency
    case memoryUsage, memoryPressure
    case gpuUsage
    case networkThroughput, networkUpload, networkDownload
    case diskActivity, diskFree
    case battery, batteryTime, systemPower
    case fanSpeed
    case uptime

    public var label: String {
        switch self {
        case .cpuUsage: return "CPU Usage"
        case .cpuTemperature: return "CPU Temperature"
        case .cpuFrequency: return "CPU Frequency"
        case .memoryUsage: return "Memory Usage"
        case .memoryPressure: return "Memory Pressure"
        case .gpuUsage: return "GPU Usage"
        case .networkThroughput: return "Network (Up & Down)"
        case .networkUpload: return "Network Upload"
        case .networkDownload: return "Network Download"
        case .diskActivity: return "Disk Activity"
        case .diskFree: return "Disk Free"
        case .battery: return "Battery"
        case .batteryTime: return "Battery Time Remaining"
        case .systemPower: return "System Power"
        case .fanSpeed: return "Fan Speed"
        case .uptime: return "Uptime"
        }
    }

    /// Which collector must be running for this readout to have data.
    public var requiredSource: CollectorID {
        switch self {
        case .cpuUsage, .cpuFrequency: return .cpu
        case .cpuTemperature, .fanSpeed: return .thermal
        case .memoryUsage, .memoryPressure: return .memory
        case .gpuUsage: return .gpu
        case .networkThroughput, .networkUpload, .networkDownload: return .network
        case .diskActivity, .diskFree: return .disk
        case .battery, .batteryTime, .systemPower: return .power
        case .uptime: return .system
        }
    }

    /// Styles that make sense for this metric. Only the metrics that keep a series
    /// can be graphed; the rest are a number, with or without their icon.
    ///
    /// The first entry is the style this metric lands on when it has no valid one:
    /// a newly added readout, or one whose stored style an older build wrote and this
    /// metric no longer supports.
    public var supportedStyles: [MenuBarDisplayStyle] {
        switch self {
        case .uptime, .batteryTime, .cpuFrequency, .diskFree:
            return [.text, .iconAndText]
        case .battery:
            // The only metric the system's own indicator can draw, and the one it
            // should draw by default, so it leads the list.
            return [.battery] + MenuBarDisplayStyle.general
        case .networkThroughput:
            // The one readout that is already two directions, so it is the one the
            // two lights can stand in for.
            return MenuBarDisplayStyle.general + [.statusDot]
        case .cpuUsage, .gpuUsage, .memoryUsage, .memoryPressure:
            // The readouts that are a fraction of a known ceiling, which is the only
            // thing a fill level can honestly draw.
            return MenuBarDisplayStyle.general + [.bar, .tile]
        default:
            return MenuBarDisplayStyle.general
        }
    }
}

/// How one readout draws.
///
/// The general styles are the number, the number's history, and the number with a mark
/// saying which metric it is. The rest each draw one shape for the metrics that shape
/// can honestly stand for: the system battery indicator for the charge, two activity
/// lights for the up-and-down network readout, and a fill level for the readouts that
/// are a fraction of a known ceiling.
public enum MenuBarDisplayStyle: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case text
    case graph
    case textAndGraph
    case iconAndText
    case battery
    case statusDot
    case bar
    /// The bar's fill level as a solid block with its label set inside it.
    case tile

    /// The styles any numeric readout can take. The indicator styles are left out
    /// because each draws one kind of metric and nothing else.
    public static let general: [MenuBarDisplayStyle] = [.text, .graph, .textAndGraph, .iconAndText]

    /// The two styles that draw a fraction as a fill level, with the caption stacked
    /// one letter to a row.
    public var drawsLevel: Bool { self == .bar || self == .tile }

    public var label: String {
        switch self {
        case .text: return "Text"
        case .graph: return "Graph"
        case .textAndGraph: return "Text & Graph"
        case .iconAndText: return "Icon & Text"
        case .battery: return "Battery Indicator"
        case .statusDot: return "Status Dot"
        case .bar: return "Compact Bar"
        case .tile: return "Tile"
        }
    }

    /// Whether a caption would add anything. It would not for the two styles that
    /// already name their metric with a glyph, and the status dots are meant to be
    /// the smallest thing on the bar, so they carry no text at all. A bar is an
    /// anonymous shape, so the caption is what says which fraction it is.
    public var supportsCaption: Bool {
        switch self {
        case .text, .graph, .textAndGraph, .bar, .tile: return true
        case .iconAndText, .battery, .statusDot: return false
        }
    }
}

public struct MenuBarItemConfig: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var metric: MenuBarMetric
    public var style: MenuBarDisplayStyle
    public var isEnabled: Bool
    /// Draw the metric's name above its number.
    public var showsCaption: Bool

    public init(id: UUID = UUID(), metric: MenuBarMetric, style: MenuBarDisplayStyle = .text,
                isEnabled: Bool = true, showsCaption: Bool = true) {
        self.id = id
        self.metric = metric
        self.style = style
        self.isEnabled = isEnabled
        self.showsCaption = showsCaption
    }

    /// Clamp a decoded config back into a coherent state — an old build may have
    /// stored a style this metric no longer supports.
    public func sanitized() -> MenuBarItemConfig {
        var copy = self
        if !metric.supportedStyles.contains(style) {
            copy.style = metric.supportedStyles.first ?? .text
        }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, metric, style, isEnabled, showsCaption
    }

    /// A file written by an older build carries a `graphWidth` and may carry a style
    /// that no longer exists. Neither is an error: the unknown key is not read, and
    /// `sanitized()` moves the retired style to one this metric still supports.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        metric = c.value(.metric, or: MenuBarMetric.cpuUsage)
        style = c.value(.style, or: MenuBarDisplayStyle.text)
        isEnabled = c.value(.isEnabled, or: true)
        showsCaption = c.value(.showsCaption, or: true)
    }
}

public struct MenuBarSettings: Sendable, Codable, Equatable {
    /// The readouts, in order. Always drawn together in one menu bar item.
    public var items: [MenuBarItemConfig]
    /// Off, and the app puts nothing in the menu bar at all: Settings is reached by
    /// launching the app again or by its hot key.
    public var isVisible: Bool

    /// Numbers are always set in a fixed-width face. Previously a toggle; a column of
    /// proportional digits shimmers as it changes, which is the single most visible
    /// cheapness tell in a stats app, and nobody was ever going to want it.
    public static let usesMonospacedDigits = true

    /// Four settings, gone. Each governed one dimension of how the bar is packed, and
    /// between them they were the reason a readout could move, resize or vanish while
    /// the user was looking at it — the one thing a menu bar must never do.
    ///
    /// Previously `usesFixedWidth`. Always on: without it every readout resizes as its
    /// own value changes and drags everything to its right along with it.
    public static let usesFixedWidth = true
    /// Previously `itemSpacing`, a 0–24 slider. 8 is the gap AppKit puts between its
    /// own status items, which is the gap this has to match to look like it belongs.
    public static let itemSpacing: Double = 8
    /// Previously `hidesIdleItems` and `idleThreshold`. A readout that removes itself
    /// when it goes quiet takes the whole bar with it every time it comes back, and
    /// the moment a metric is worth watching is not reliably the moment it is high.
    public static let hidesIdleItems = false

    public init(items: [MenuBarItemConfig] = MenuBarSettings.defaultItems,
                isVisible: Bool = true) {
        self.items = items
        self.isVisible = isVisible
    }

    /// CPU, its temperature, GPU, and the battery.
    ///
    /// Network throughput stays out: it is by far the widest element — two values plus
    /// units — and a menu bar item wider than everything Apple ships gets silently
    /// dropped on a notched display when a few other extras are present. It is one
    /// click away in Settings for those who want it.
    ///
    /// The three numbers carry their name above their number rather than an icon beside
    /// it. An icon is a guess the reader has to make — a chip glyph is CPU to whoever
    /// drew it and "some hardware" to everyone else — while "CPU" is four narrow
    /// characters set at eight points, above the number, in a column the number was
    /// already paying for. No sparkline: at 34pt wide it reads as a scribble, and it
    /// was the single widest element left.
    ///
    /// The battery is the exception and takes no caption and no number. It draws as the
    /// system's own indicator, which every user already reads without being told what
    /// it is or what the fill means.
    ///
    /// Only a fresh install sees this. Anyone with a settings file already has their own
    /// `menuBar.items` and keeps them. The App Store's copy, which cannot read the
    /// temperature, starts without it.
    public static let defaultItems: [MenuBarItemConfig] = [
        MenuBarItemConfig(metric: .cpuUsage, style: .text, showsCaption: true),
        MenuBarItemConfig(metric: .cpuTemperature, style: .text, showsCaption: true),
        MenuBarItemConfig(metric: .gpuUsage, style: .text, showsCaption: true),
        MenuBarItemConfig(metric: .battery, style: .battery, showsCaption: false),
    ].filter { Capabilities.readsSensors || $0.metric.requiredSource != .thermal }

    public var enabledItems: [MenuBarItemConfig] { items.filter(\.isEnabled) }

    private enum CodingKeys: String, CodingKey {
        case items, isVisible
    }

    /// Files written before the packing settings were removed still load: the keys
    /// they carry for spacing, fixed width and quiet mode are simply not read, and an
    /// unknown key has never been an error here.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedItems = c.value(.items, or: MenuBarSettings.defaultItems)
        // An empty menu bar would leave the user with no way back into the app.
        items = decodedItems.isEmpty ? MenuBarSettings.defaultItems : decodedItems.map { $0.sanitized() }
        isVisible = c.value(.isVisible, or: true)
    }
}

// MARK: - Panel

public enum PanelModule: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case cpu, memory, gpu, network, disk, battery, thermal, processes, system

    public var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .gpu: return "GPU"
        case .network: return "Network"
        case .disk: return "Disk"
        case .battery: return "Battery"
        case .thermal: return "Temperature"
        case .processes: return "Top Processes"
        case .system: return "System"
        }
    }

    public var requiredSource: CollectorID {
        switch self {
        case .cpu: return .cpu
        case .memory: return .memory
        case .gpu: return .gpu
        case .network: return .network
        case .disk: return .disk
        case .battery: return .power
        case .thermal: return .thermal
        case .processes: return .processes
        case .system: return .system
        }
    }

    public var symbolName: String { requiredSource.symbolName }
}

/// Which layout the click-down panel draws.
public enum PanelStyle: String, Sendable, Codable, CaseIterable, Equatable {
    /// A grid of cards in different sizes, with a detail card beside the panel on hover.
    case bento
    /// A smaller grid of the cards' compact designs, arranged on its own.
    case bentoSmall
    /// The inside of a MacBook seen from above, every part showing how hard it is
    /// working and how hot it is, with the bento detail on hover.
    case macbook
    /// Every design of one bento card at a time, for checking how each lays out.
    case debug

    public var label: String {
        switch self {
        case .bento: return "Bento"
        case .bentoSmall: return "Bento Small"
        case .macbook: return "MacBook"
        case .debug: return "Debug"
        }
    }
}

/// What the panel remembers between openings.
///
/// The panel used to be configurable — module order, which modules were on, width,
/// process row count and sort, sparklines, focus behaviour, and then which modules were
/// unfolded in its first, list-shaped layouts. What remains is the layout, and the two
/// bento arrangements, which the user sets in the panel itself rather than here.
public struct PanelSettings: Sendable, Codable, Equatable {
    /// Draw the module's history in the detail beside the panel.
    public var showsHistoryChart: Bool
    /// The panel's layout.
    public var style: PanelStyle
    /// The bento layout's cards, in order, each in one of its designs. Arranged in the
    /// panel itself, in its edit mode.
    public var bentoTiles: [BentoTile]
    /// Bento Small's cards, arranged the same way and kept apart from Bento's.
    public var bentoSmallTiles: [BentoTile]

    /// The narrowest a detail or panel window starts at before it has measured itself.
    public static let width: Double = 380

    public init(showsHistoryChart: Bool = true, style: PanelStyle = .bento,
                bentoTiles: [BentoTile] = BentoLayout.defaultTiles,
                bentoSmallTiles: [BentoTile] = BentoLayout.defaultSmallTiles) {
        self.showsHistoryChart = showsHistoryChart
        self.style = style
        self.bentoTiles = BentoLayout.sanitized(bentoTiles)
        self.bentoSmallTiles = BentoLayout.sanitized(bentoSmallTiles)
    }

    /// Every module, in declaration order.
    public var visibleModules: [PanelModule] { PanelModule.allCases }

    private enum CodingKeys: String, CodingKey {
        case showsHistoryChart, style, bentoTiles, bentoSmallTiles
    }

    /// Decoded leniently: settings files written before carry keys that are no longer
    /// read, and a layout that no longer exists, Original or List, opens as Bento.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showsHistoryChart = c.value(.showsHistoryChart, or: true)
        style = c.value(.style, or: .bento)
        bentoTiles = BentoLayout.sanitized(c.value(.bentoTiles, or: BentoLayout.defaultTiles))
        bentoSmallTiles = BentoLayout.sanitized(c.value(.bentoSmallTiles, or: BentoLayout.defaultSmallTiles))
    }
}

// MARK: - Charts

public enum ChartStyle: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case line, filledLine, bars

    public var label: String {
        switch self {
        case .line: return "Line"
        case .filledLine: return "Filled Line"
        case .bars: return "Bars"
        }
    }
}

/// What the charts remember.
///
/// Two settings, where there were six. Grid, value labels, curve smoothing and
/// adaptive scaling were each a toggle governing one detail of how a 28-point
/// sparkline is drawn — four decisions the app is better placed to make than the
/// user, and four rows of settings standing between them and the two that change
/// what a chart actually says. They are constants now, at the values every one of
/// them shipped switched on.
public struct ChartSettings: Sendable, Codable, Equatable {
    /// Seconds of history retained and drawn.
    public var historyDuration: TimeInterval
    public var style: ChartStyle

    /// Previously `showsGrid`.
    public static let showsGrid = true
    /// Previously `usesAdaptiveScale`: rate charts scale to the peak in the window,
    /// because a rate has no maximum to scale against instead.
    public static let usesAdaptiveScale = true
    /// Previously `showsValueLabels`.
    public static let showsValueLabels = true
    /// Previously `smoothsCurves`. Smooths the drawn line only; samples are never
    /// averaged, so a spike is still a spike in the number beside it.
    public static let smoothsCurves = true

    public init(historyDuration: TimeInterval = 300,
                style: ChartStyle = .filledLine) {
        self.historyDuration = historyDuration
        self.style = style
    }

    public static let allowedDurations: [TimeInterval] = [60, 300, 600, 1800, 3600]

    private enum CodingKeys: String, CodingKey {
        case historyDuration, style
    }

    /// Files written before the drawing toggles were removed still load: the keys they
    /// carry are simply not read, and an unknown key has never been an error here.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        historyDuration = min(max(c.value(.historyDuration, or: 300.0), 30), 3600)
        style = c.value(.style, or: ChartStyle.filledLine)
    }
}

// MARK: - Notifications

public enum ThresholdMetric: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case cpuUsage, memoryPressure, diskFree, batteryLow, batteryFull, cpuTemperature, thermalPressure

    public var label: String {
        switch self {
        case .cpuUsage: return "Sustained CPU usage above"
        case .memoryPressure: return "Memory pressure above"
        case .diskFree: return "Startup disk free space below"
        case .batteryLow: return "Battery drops below"
        case .batteryFull: return "Battery reaches"
        case .cpuTemperature: return "CPU temperature above"
        case .thermalPressure: return "Thermal pressure reaches"
        }
    }

    public var unitSuffix: String {
        switch self {
        case .cpuUsage, .memoryPressure, .batteryLow, .batteryFull: return "%"
        case .diskFree: return "GB"
        case .cpuTemperature: return "°"
        case .thermalPressure: return ""
        }
    }

    public var defaultThreshold: Double {
        switch self {
        case .cpuUsage: return 90
        case .memoryPressure: return 80
        case .diskFree: return 10
        case .batteryLow: return 20
        case .batteryFull: return 100
        case .cpuTemperature: return 95
        case .thermalPressure: return 2
        }
    }

    public var requiredSource: CollectorID {
        switch self {
        case .cpuUsage: return .cpu
        case .memoryPressure: return .memory
        case .diskFree: return .disk
        case .batteryLow, .batteryFull: return .power
        case .cpuTemperature, .thermalPressure: return .thermal
        }
    }
}

public struct ThresholdRule: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var metric: ThresholdMetric
    public var threshold: Double
    public var isEnabled: Bool
    /// Seconds the condition must hold before notifying, so a one-second CPU spike
    /// while launching an app does not fire an alert.
    public var sustainedFor: TimeInterval
    /// Minimum seconds between repeat notifications for this rule.
    public var cooldown: TimeInterval

    public init(id: UUID = UUID(), metric: ThresholdMetric, threshold: Double? = nil,
                isEnabled: Bool = false, sustainedFor: TimeInterval = 30,
                cooldown: TimeInterval = 900) {
        self.id = id
        self.metric = metric
        self.threshold = threshold ?? metric.defaultThreshold
        self.isEnabled = isEnabled
        self.sustainedFor = sustainedFor
        self.cooldown = cooldown
    }

    private enum CodingKeys: String, CodingKey {
        case id, metric, threshold, isEnabled, sustainedFor, cooldown
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        metric = c.value(.metric, or: ThresholdMetric.cpuUsage)
        threshold = c.value(.threshold, or: metric.defaultThreshold)
        isEnabled = c.value(.isEnabled, or: false)
        sustainedFor = min(max(c.value(.sustainedFor, or: 30.0), 0), 3600)
        cooldown = min(max(c.value(.cooldown, or: 900.0), 60), 86400)
    }
}

public struct NotificationSettings: Sendable, Codable, Equatable {
    public var isEnabled: Bool
    public var rules: [ThresholdRule]

    public init(isEnabled: Bool = false, rules: [ThresholdRule] = NotificationSettings.defaultRules) {
        self.isEnabled = isEnabled
        self.rules = rules
    }

    public static var defaultRules: [ThresholdRule] {
        ThresholdMetric.allCases.map { ThresholdRule(metric: $0) }
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, rules }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = c.value(.isEnabled, or: false)
        var decoded = c.value(.rules, or: NotificationSettings.defaultRules)
        // Add rules for any metric introduced since the file was written.
        let present = Set(decoded.map(\.metric))
        for metric in ThresholdMetric.allCases where !present.contains(metric) {
            decoded.append(ThresholdRule(metric: metric))
        }
        rules = decoded
    }

    public var enabledRules: [ThresholdRule] { rules.filter(\.isEnabled) }
}

// MARK: - Shortcuts

/// A recorded key combination. Stored as a raw key code plus modifier bitmask so it
/// survives keyboard layout changes.
public struct KeyboardShortcut: Sendable, Codable, Equatable, Hashable {
    public var keyCode: UInt16
    public var modifierFlags: UInt
    public var characters: String

    public init(keyCode: UInt16, modifierFlags: UInt, characters: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.characters = characters
    }
}

public enum ShortcutAction: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case togglePanel = "togglePanel"
    case toggleMenuBarItem = "toggleMenuBarItem"
    case openSettings = "openSettings"

    public var label: String {
        switch self {
        case .togglePanel: return "Show / Hide Panel"
        case .toggleMenuBarItem: return "Show / Hide Menu Bar Item"
        case .openSettings: return "Open Settings"
        }
    }
}

public struct ShortcutSettings: Sendable, Codable, Equatable {
    public var bindings: [ShortcutAction: KeyboardShortcut]

    public init(bindings: [ShortcutAction: KeyboardShortcut] = [:]) {
        self.bindings = bindings
    }

    private enum CodingKeys: String, CodingKey { case bindings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bindings = c.value(.bindings, or: [:])
    }
}

// MARK: - General

public struct GeneralSettings: Sendable, Codable, Equatable {
    /// Seconds between sampling cycles. Individual collectors may run slower.
    public var updateInterval: TimeInterval
    /// Off until the user turns it on: the Mac App Store does not let an app start
    /// itself at login without being asked to.
    public var launchAtLogin: Bool
    public var appearance: AppearanceMode
    public var temperatureUnit: TemperatureUnit
    public var networkRateUnit: NetworkRateUnit
    public var byteUnitStyle: ByteUnitStyle
    public var showsPercentSign: Bool
    /// Drop to a quarter cadence when the menu bar item is not visible.
    public var throttlesWhenOccluded: Bool
    /// Suspend sampling entirely while on battery below a threshold.
    public var pausesOnLowPower: Bool
    /// Fetch the public IP address: the one feature that leaves the machine.
    public var fetchesPublicIP: Bool
    public var showsDockIcon: Bool
    /// Look for a newer release once a day. Only the copy downloaded from GitHub does:
    /// the App Store copy is updated by the store, and a build from source by its builder.
    public var checksForUpdates: Bool

    public init(updateInterval: TimeInterval = 2,
                launchAtLogin: Bool = false,
                appearance: AppearanceMode = .system,
                temperatureUnit: TemperatureUnit = .celsius,
                networkRateUnit: NetworkRateUnit = .bytes,
                byteUnitStyle: ByteUnitStyle = .decimal,
                showsPercentSign: Bool = true,
                throttlesWhenOccluded: Bool = true,
                pausesOnLowPower: Bool = false,
                fetchesPublicIP: Bool = false,
                showsDockIcon: Bool = false,
                checksForUpdates: Bool = true) {
        self.updateInterval = updateInterval
        self.launchAtLogin = launchAtLogin
        self.appearance = appearance
        self.temperatureUnit = temperatureUnit
        self.networkRateUnit = networkRateUnit
        self.byteUnitStyle = byteUnitStyle
        self.showsPercentSign = showsPercentSign
        self.throttlesWhenOccluded = throttlesWhenOccluded
        self.pausesOnLowPower = pausesOnLowPower
        self.fetchesPublicIP = fetchesPublicIP
        self.showsDockIcon = showsDockIcon
        self.checksForUpdates = checksForUpdates
    }

    public static let allowedIntervals: [TimeInterval] = [0.5, 1, 2, 3, 5, 10, 30]

    private enum CodingKeys: String, CodingKey {
        case updateInterval, launchAtLogin, appearance, temperatureUnit, networkRateUnit
        case byteUnitStyle, showsPercentSign, throttlesWhenOccluded, pausesOnLowPower
        case fetchesPublicIP, showsDockIcon, checksForUpdates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updateInterval = min(max(c.value(.updateInterval, or: 2.0), 0.5), 60)
        launchAtLogin = c.value(.launchAtLogin, or: false)
        appearance = c.value(.appearance, or: AppearanceMode.system)
        temperatureUnit = c.value(.temperatureUnit, or: TemperatureUnit.celsius)
        networkRateUnit = c.value(.networkRateUnit, or: NetworkRateUnit.bytes)
        byteUnitStyle = c.value(.byteUnitStyle, or: ByteUnitStyle.decimal)
        showsPercentSign = c.value(.showsPercentSign, or: true)
        throttlesWhenOccluded = c.value(.throttlesWhenOccluded, or: true)
        pausesOnLowPower = c.value(.pausesOnLowPower, or: false)
        fetchesPublicIP = c.value(.fetchesPublicIP, or: false)
        showsDockIcon = c.value(.showsDockIcon, or: false)
        checksForUpdates = c.value(.checksForUpdates, or: true)
    }
}

// MARK: - Root

public struct Settings: Sendable, Codable, Equatable {
    /// Bumped when a migration is needed. Unknown future versions are loaded
    /// leniently rather than discarded.
    public var schemaVersion: Int
    public var general: GeneralSettings
    public var menuBar: MenuBarSettings
    public var panel: PanelSettings
    public var charts: ChartSettings
    public var notifications: NotificationSettings
    public var shortcuts: ShortcutSettings

    public static let currentSchemaVersion = 1

    public init(schemaVersion: Int = Settings.currentSchemaVersion,
                general: GeneralSettings = .init(),
                menuBar: MenuBarSettings = .init(),
                panel: PanelSettings = .init(),
                charts: ChartSettings = .init(),
                notifications: NotificationSettings = .init(),
                shortcuts: ShortcutSettings = .init()) {
        self.schemaVersion = schemaVersion
        self.general = general
        self.menuBar = menuBar
        self.panel = panel
        self.charts = charts
        self.notifications = notifications
        self.shortcuts = shortcuts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, general, menuBar, panel, charts, notifications, shortcuts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, or: Settings.currentSchemaVersion)
        general = c.value(.general, or: GeneralSettings())
        menuBar = c.value(.menuBar, or: MenuBarSettings())
        panel = c.value(.panel, or: PanelSettings())
        charts = c.value(.charts, or: ChartSettings())
        notifications = c.value(.notifications, or: NotificationSettings())
        shortcuts = c.value(.shortcuts, or: ShortcutSettings())
    }

    /// Collectors that must run to satisfy everything currently on screen.
    ///
    /// This drives the engine's enabled-source set, and is why a user who only
    /// wants a CPU readout never pays for IOKit battery or SMC sensor polling.
    public func requiredSources(panelVisible: Bool) -> Set<CollectorID> {
        var sources = Set<CollectorID>()
        for item in menuBar.enabledItems { sources.insert(item.metric.requiredSource) }
        if panelVisible {
            for module in panel.visibleModules { sources.insert(module.requiredSource) }
        } else if panel.showsHistoryChart {
            // The panel's charts draw the last day by the clock, and a minute nobody
            // sampled is a hole in it. So the charted modules keep sampling while the
            // panel is closed. The process list is not charted and is the expensive
            // one, so it still waits for the panel.
            for module in panel.visibleModules where module != .processes {
                sources.insert(module.requiredSource)
            }
        }
        if notifications.isEnabled {
            for rule in notifications.enabledRules { sources.insert(rule.metric.requiredSource) }
        }
        // System info is cheap, static, and needed for the about/uptime readouts.
        sources.insert(.system)
        return sources
    }

    /// Number of retained samples implied by the chart history and update interval.
    public var historyCapacity: Int {
        let interval = max(general.updateInterval, 0.5)
        return min(max(Int(charts.historyDuration / interval) + 2, 30), 4096)
    }
}
