// Every vanilla mesh whose collision uses `bhkNiTriStripsShape` stores its strip vertices
// in game units: placed by their shape transform, they lie about where the drawn mesh does.
// A Havok scale on them once made a fallen pine's collision span many cells.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
import simd
import Testing

struct NIFTriStripsCollisionRealDataTests {
    private static let marker = Data("bhkNiTriStripsShape".utf8)
    /// Its data moves one of its two strip shapes 146.3 Havok units (10240 game units) away.
    private static let storedFarAway: Set = [
        "meshes\\dungeons\\caves\\green\\epic\\cavegemid01.nif"
    ]

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func stripVerticesAreInGameUnits() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let paths = vfs.archiveEntries().map(\.path)
            .filter { $0.hasPrefix("meshes\\") && $0.hasSuffix(".nif") }
        var checked: [String] = []
        for path in paths {
            let data = try vfs.contents(forPath: path)
            guard data.range(of: Self.marker) != nil, !Self.storedFarAway.contains(path)
            else { continue }
            let file = try NIFFile(data: data)
            guard let drawn = attempt({ try ModelBounds.containing(model: file.model()) })
            else { continue }
            checked.append(path)
            let room = (drawn.max - drawn.min) + SIMD3(repeating: 1024)
            for vertices in Self.soups(file.collisionModel()) where !vertices.isEmpty {
                let low = vertices.reduce(SIMD3(repeating: Float.infinity)) { simd_min($0, $1) }
                let high = vertices.reduce(SIMD3(repeating: -Float.infinity)) { simd_max($0, $1) }
                let fits = all(low .>= drawn.min - room) && all(high .<= drawn.max + room)
                #expect(fits, "\(path): strip vertices \(low) to \(high)")
            }
        }
        #expect(checked.contains("meshes\\landscape\\trees\\treepineforestuprooted01.nif"))
        #expect(checked.count >= 4, "\(checked)")
    }

    /// The vertices of each triangle shape, placed in the model by the shape's transform.
    private static func soups(_ model: NIFCollisionModel) -> [[SIMD3<Float>]] {
        model.bodies.flatMap(\.shapes).compactMap { shape in
            guard case let .triangleSoup(vertices, _) = shape.geometry else { return nil }
            return vertices.map {
                let placed = shape.transform * SIMD4($0, 1)
                return SIMD3(placed.x, placed.y, placed.z)
            }
        }
    }
}
