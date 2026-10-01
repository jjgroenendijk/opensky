// One real Whiterun guard from the user's install, shared by the perception and
// combat suites so both use the same guard: its cell, the lowest guard ACHR in
// it, and line of sight over the cell's real collision.

import Foundation
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import simd

enum WhiterunGuardFixture {
    /// Whiterun's own worldspace, and the cell the vanilla guard posts stand in
    /// — the numbers `openskycli actor --worldspace WhiterunWorld --x 6 --y 0`
    /// reports on this install.
    static let worldspace = "WhiterunWorld"
    static let cell = CellCoordinate(x: 6, y: 0)
    /// Every vanilla Whiterun guard's base record is named this way, which is
    /// how one is found without pinning a FormID that a patch could move.
    static let editorIDPrefix = "GuardWhiterun"

    /// One located guard: its runtime identity, its placement and its base
    /// record's editor ID.
    struct LocatedGuard {
        let key: ReferenceKey
        let actor: PlacedActor
        let editorID: String
    }

    /// The guard's own cell, built through the production path so the collision
    /// a sight line is traced against is the real thing.
    static func buildCell(root: GameDataRoot, device: MTLDevice) throws -> CellScene {
        let fileSystem = VirtualFileSystem(root: root)
        let textures = try TextureLibrary(fileSystem: fileSystem, device: device)
        let builder = try CellSceneBuilder(
            file: ESMFile(url: root.dataURL.appending(path: "Skyrim.esm")),
            meshes: MeshLibrary(fileSystem: fileSystem, device: device, textures: textures),
            textures: textures,
            fileSystem: fileSystem
        )
        return try builder.buildScene(
            worldspaceEditorID: worldspace, gridX: cell.x, gridY: cell.y
        )
    }

    /// The lowest-keyed ACHR in `scene` whose resolved base NPC_ is named like
    /// a Whiterun guard. Lowest-keyed so a rebuild picks the same one.
    static func locate(in scene: CellScene, templates: ActorTemplateResolver) -> LocatedGuard? {
        for entry in scene.references.sortedEntries() {
            guard
                let actor = entry.placedActor,
                let editorID = templates.actors[actor.base.rawValue]?.editorID,
                editorID.hasPrefix(editorIDPrefix)
            else { continue }
            return LocatedGuard(key: entry.key, actor: actor, editorID: editorID)
        }
        return nil
    }

    /// Actor templates for the master file, which is what resolves an ACHR's
    /// base record to an editor ID.
    static func templates(root: GameDataRoot) throws -> ActorTemplateResolver {
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        return ActorTemplateResolver.build(
            from: file, localized: (try? file.pluginHeader().isLocalized) ?? false
        )
    }

    /// The blocked predicate `FakePerceptionWorld` takes, over real geometry.
    static func blockedPredicate(
        against collision: StaticCollisionSet
    ) -> (SIMD3<Float>, SIMD3<Float>) -> Bool {
        { origin, destination in
            let offset = destination - origin
            guard
                simd_length(offset) > 0,
                let ray = InteractionRay(
                    origin: origin,
                    direction: offset,
                    maximumDistance: simd_length(offset)
                )
            else { return false }
            return InteractionRaycaster.nearestHit(
                ray: ray, shapes: collision.candidates(overlapping: ray.bounds)
            ) != nil
        }
    }
}
