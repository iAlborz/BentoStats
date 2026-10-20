import Testing
import Foundation
@testable import AirStatKit

@Suite("Bento layout")
struct BentoLayoutTests {

    private func place(_ tiles: [BentoTile]) -> [BentoTileKind: BentoPlacement] {
        let packed = BentoLayout.pack(tiles).placements
        return Dictionary(uniqueKeysWithValues: tiles.map { ($0.kind, packed[$0.id]!) })
    }

    @Test("the default cards pack into the panel as it was designed")
    func defaultMatchesDesign() {
        let placed = place(BentoLayout.defaultTiles)
        #expect(BentoLayout.pack(BentoLayout.defaultTiles).rows == 4)
        #expect(placed[.cpu] == BentoPlacement(column: 0, row: 0, columns: 2, rows: 2))
        #expect(placed[.memory] == BentoPlacement(column: 2, row: 0, columns: 2, rows: 2))
        #expect(placed[.disk] == BentoPlacement(column: 4, row: 0, columns: 2, rows: 1))
        #expect(placed[.battery] == BentoPlacement(column: 4, row: 1, columns: 2, rows: 1))
        #expect(placed[.gpu] == BentoPlacement(column: 0, row: 2, columns: 2, rows: 2))
        #expect(placed[.network] == BentoPlacement(column: 2, row: 2, columns: 2, rows: 1))
        #expect(placed[.thermal] == BentoPlacement(column: 4, row: 2, columns: 1, rows: 2))
        #expect(placed[.settings] == BentoPlacement(column: 5, row: 2, columns: 1, rows: 1))
        #expect(placed[.system] == BentoPlacement(column: 2, row: 3, columns: 2, rows: 1))
        #expect(placed[.quit] == BentoPlacement(column: 5, row: 3, columns: 1, rows: 1))
    }

    @Test("every card has two to five designs, the first its default, all its own")
    func designsPerCard() {
        for kind in BentoTileKind.allCases {
            #expect((2...5).contains(kind.variants.count), "\(kind)")
            #expect(kind.defaultVariant == kind.variants[0])
            #expect(kind.variants.allSatisfy { $0.kind == kind })
        }
        #expect(BentoLayout.defaultTiles.allSatisfy { $0.variant == $0.kind.defaultVariant })
    }

    @Test("no arrangement overlaps or runs off the grid")
    func neverOverlaps() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let tiles = (0..<Int.random(in: 1...14, using: &generator)).map { _ in
                let kind = BentoTileKind.allCases.randomElement(using: &generator)!
                return BentoTile(kind: kind, variant: kind.variants.randomElement(using: &generator)!)
            }
            let packed = BentoLayout.pack(tiles)
            var cells = Set<[Int]>()
            for tile in tiles {
                let p = packed.placements[tile.id]!
                #expect(p.column >= 0 && p.column + p.columns <= BentoLayout.columns)
                for r in p.row..<p.row + p.rows {
                    for c in p.column..<p.column + p.columns {
                        #expect(cells.insert([c, r]).inserted, "two cards share a cell")
                    }
                }
            }
            #expect(cells.allSatisfy { $0[1] < packed.rows })
        }
    }

    @Test("a smaller card fills the hole a larger one left")
    func fillsHoles() {
        let tiles = [BentoTile(kind: .cpu, variant: .cpuChipHistory), BentoTile(kind: .gpu, variant: .gpuDie),
                     BentoTile(kind: .settings)]
        let placed = place(tiles)
        #expect(placed[.gpu] == BentoPlacement(column: 4, row: 0, columns: 2, rows: 2))
        #expect(placed[.settings] == BentoPlacement(column: 0, row: 2, columns: 1, rows: 1))
    }

    @Test("Settings and Quit always stay, and a card cannot wear another card's design")
    func sanitizedKeepsTheWayOut() {
        var stray = BentoTile(kind: .cpu)
        stray.variant = .memoryPressure
        let tiles = BentoLayout.sanitized([stray, BentoTile(kind: .quit, variant: .quitWide)])
        #expect(tiles.contains { $0.kind == .settings })
        #expect(tiles[0].variant == .cpuChip)
        #expect(tiles[1].variant == .quitWide)
    }

    @Test("settings written before the editable grid load the designed layout")
    func olderSettingsLoadTheDefault() throws {
        let json = #"{"style":"bento","showsHistoryChart":true}"#
        let panel = try JSONDecoder().decode(PanelSettings.self, from: Data(json.utf8))
        #expect(panel.bentoTiles == BentoLayout.defaultTiles)
    }

    @Test("a card saved as a size and style becomes the design of that size")
    func sizesBecomeDesigns() throws {
        let id = UUID()
        let wide = #"{"id":"\#(id)","kind":"cpu","size":"wide","style":"number"}"#
        #expect(try JSONDecoder().decode(BentoTile.self, from: Data(wide.utf8)).variant == .cpuLoad)
        let gone = #"{"id":"\#(id)","kind":"network","size":"extraWide","style":"graphic"}"#
        #expect(try JSONDecoder().decode(BentoTile.self, from: Data(gone.utf8)).variant == .networkSpeeds)
        let tile = BentoTile(kind: .battery, variant: .batteryInside)
        #expect(try JSONDecoder().decode(BentoTile.self, from: JSONEncoder().encode(tile)) == tile)
    }

    @Test("a size snaps to the nearest one the card's designs come in")
    func nearestSize() {
        #expect(BentoTileSize.nearest(columns: 3, rows: 1, in: BentoTileKind.cpu.sizes) == .wide)
        #expect(BentoTileSize.nearest(columns: 4, rows: 3, in: BentoTileKind.cpu.sizes) == .extraWide)
        #expect(BentoTileSize.nearest(columns: 2, rows: 2, in: BentoTileKind.quit.sizes) == .wide)
    }

    @Test("every layout is saved and read back, and the retired ones open as Bento")
    func layouts() throws {
        for style in PanelStyle.allCases {
            var panel = PanelSettings()
            panel.style = style
            let decoded = try JSONDecoder().decode(PanelSettings.self, from: JSONEncoder().encode(panel))
            #expect(decoded.style == style)
        }
        for retired in ["original", "list"] {
            let json = #"{"style":"\#(retired)"}"#
            #expect(try JSONDecoder().decode(PanelSettings.self, from: Data(json.utf8)).style == .bento)
        }
        #expect(PanelSettings().style == .bento)
    }

    @Test("Bento Small starts as the compact designs, three full rows of five")
    func bentoSmallDefault() {
        let tiles = BentoLayout.defaultSmallTiles
        #expect(tiles.allSatisfy { $0.size == .small || $0.size == .wide })
        let packed = BentoLayout.pack(tiles, columns: BentoLayout.smallColumns)
        #expect(packed.rows == 3)
        #expect(tiles.reduce(0) { $0 + $1.size.columns * $1.size.rows } == 15)
        #expect(PanelSettings().bentoSmallTiles == tiles)
    }
}
