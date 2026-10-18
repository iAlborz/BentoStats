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

    @Test("no arrangement overlaps or runs off the grid")
    func neverOverlaps() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let tiles = (0..<Int.random(in: 1...14, using: &generator)).map { _ in
                let kind = BentoTileKind.allCases.randomElement(using: &generator)!
                return BentoTile(kind: kind, size: kind.sizes.randomElement(using: &generator)!)
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
        let tiles = [BentoTile(kind: .cpu, size: .extraWide), BentoTile(kind: .gpu, size: .large),
                     BentoTile(kind: .settings, size: .small)]
        let placed = place(tiles)
        #expect(placed[.gpu] == BentoPlacement(column: 4, row: 0, columns: 2, rows: 2))
        #expect(placed[.settings] == BentoPlacement(column: 0, row: 2, columns: 1, rows: 1))
    }

    @Test("Settings and Quit always stay, and a size a card cannot take is replaced")
    func sanitizedKeepsTheWayOut() {
        let tiles = BentoLayout.sanitized([BentoTile(kind: .cpu), BentoTile(kind: .quit, size: .large)])
        #expect(tiles.contains { $0.kind == .settings })
        #expect(tiles.first { $0.kind == .quit }?.size == .small)
    }

    @Test("settings written before the editable grid load the designed layout")
    func olderSettingsLoadTheDefault() throws {
        let json = #"{"style":"bento","showsHistoryChart":true}"#
        let panel = try JSONDecoder().decode(PanelSettings.self, from: Data(json.utf8))
        #expect(panel.bentoTiles == BentoLayout.defaultTiles)
    }

    @Test("a size snaps to the nearest one the card can take")
    func nearestSize() {
        #expect(BentoTileSize.nearest(columns: 3, rows: 1, in: BentoTileKind.cpu.sizes) == .wide)
        #expect(BentoTileSize.nearest(columns: 4, rows: 3, in: BentoTileKind.cpu.sizes) == .extraWide)
        #expect(BentoTileSize.nearest(columns: 2, rows: 2, in: BentoTileKind.quit.sizes) == .wide)
    }
}
