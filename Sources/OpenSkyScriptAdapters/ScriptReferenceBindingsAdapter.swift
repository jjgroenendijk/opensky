import Foundation
import MetalKit
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyScripting
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `ScriptReferenceBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptReferenceBindingsHost: AnyObject {
    var combat: any CombatPort { get }
    var combatWorld: any CombatWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `ScriptWorldAdapter`, over its own narrow host.
public struct ScriptReferenceBindingsAdapter {
    public unowned let owner: ScriptWorldAdapter
    public unowned let game: any ScriptReferenceBindingsHost
}

extension ScriptReferenceBindingsAdapter {
    public func wireReferenceRules(_ hooks: inout PapyrusGameNatives, provider: WorldDataStores) {
        hooks.clearExtraArrows = { [weak game] actor in
            guard let game, let host = game.streamer?.referenceEntry(key: actor)?.formID else {
                return 0
            }
            return game.combat.archery?.projectiles.removeArrows(stuckIn: host) ?? 0
        }
        let impacts = provider.footstepStore.map(MeleeImpactResolver.init(footsteps:))
        hooks.playImpact = { [weak owner] dataSet, pick in
            guard
                owner != nil, let impacts, let id = game.scripts.bridge?.localFormID(of: dataSet),
                let hit = impactHit(of: pick),
                let impact = impacts.resolve(dataSet: id, material: hit.material)
            else { return false }
            game.combatWorld.playImpact(impact, at: hit.position)
            return true
        }
        hooks.resetCell = { [weak game] cell in
            guard
                let game, let reset = game.gameSession?.cellReset,
                let id = game.scripts.bridge?.localFormID(of: cell),
                let location = game.streamer?.placedRecords?.location(ofCell: id)
            else { return false }
            reset.flagForReset(location)
            return true
        }
    }

    /// Where `PlayImpactEffect`'s pick meets a surface. A node not readable now picks
    /// from the reference. "Local" rotation is the node's turn inside its parent node.
    private func impactHit(of pick: PapyrusImpactPick) -> ImpactPickHit? {
        guard
            let streamer = game.streamer,
            let state = game.scripts.bridge?.referenceState(for: pick.source)
        else { return nil }
        let node = pick.node.isEmpty ? nil : owner.nodeBindings.readyNode(
            of: pick.source,
            named: pick.node
        )
        let origin = node.map { simd_make_float3($0.world.columns.3) }
            ?? state.transform.position
        var direction = pick.direction
        if let node, pick.appliesNodeRotation {
            let turn = pick.usesNodeLocalRotation ? node.local : node.world
            let turned = turn * SIMD4(direction, 0)
            direction = SIMD3(turned.x, turned.y, turned.z)
        }
        let query = ShapeSweepQuery.sphere(
            center: origin, radius: 1, direction: direction, maximumDistance: pick.length
        )
        let solid = game.combatWorld.sweep(query).map {
            (
                distance: $0.distance,
                hit: ImpactPickHit(position: $0.position, material: $0.material)
            )
        }
        return ImpactPick.resolve(
            origin: origin, direction: direction, length: pick.length, staticHit: solid
        ) { point in
            streamer.sampleTerrain(at: point).map { (height: $0.height, material: $0.material) }
        }
    }
}
