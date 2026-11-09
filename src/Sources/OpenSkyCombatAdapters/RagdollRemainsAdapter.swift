import OpenSkyActorPresentation
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEffects
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// What `RagdollRemainsAdapter` reads from the session.
@MainActor
public protocol RagdollRemainsHost: AnyObject {
    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)?
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]?
    var effects: any EffectsPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var inventory: any InventoryPort { get }
    var menuWorld: any MenuWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldData: WorldDataStores? { get }
}

/// Part of `RagdollWorldAdapter`, over its own narrow host.
public struct RagdollRemainsAdapter {
    public let game: any RagdollRemainsHost
    public let poseReads: RagdollPoseReadsAdapter
}

extension RagdollRemainsAdapter {
    /// A dropped weapon rests this far above the feet, so it does not sink into the floor.
    public static let droppedWeaponLift: Float = 4
    /// `BPND` part type 1 is the head (CK wiki "Skyrim bodyparts number").
    public static let headPartType: UInt8 = 1
    /// `BPND` flag 0x01: the part can be severed.
    public static let severableFlag: UInt8 = 0x01

    /// Only a drawn weapon falls; a sheathed one stays on the belt.
    public func dropWeapon(of key: ReferenceKey) -> Bool {
        let streamer = game.streamer
        guard
            game.actorPlayback(for: key)?.weaponsDrawn == true,
            let holder = streamer.inventoryHolder(of: key),
            let actor = streamer.referenceEntry(key: key)?.placedActor,
            let cell = streamer.cellLocation(of: key)
        else { return false }
        let feet = actor.placement.position
        var position = feet
        if
            let pose = poseReads.ragdollPose(of: key),
            let hand = game.animatedPose(for: key)?[ActorAttachmentBone.drawnWeapon]
        {
            let world = pose.actorToWorld * hand.columns.3
            position = SIMD3(world.x, world.y, feet.z)
        }
        position.z += Self.droppedWeaponLift
        return game.inventory.dropWeapon(
            of: holder,
            at: DropPlacement(location: cell, position: position, rotation: .zero)
        ) != nil
    }

    /// The head part of the race's `BPTD`: part type 1, or a part marked severable.
    public func severableNode(of key: ReferenceKey) -> String? {
        guard let parts = bodyParts(of: key)?.record.parts else { return nil }
        let head = parts.first { $0.nodeData?.partType == Self.headPartType }
            ?? parts.first { ($0.nodeData?.flags ?? 0) & Self.severableFlag != 0 }
        return head?.nodeName
    }

    /// The race's own cut: the part's severable explosion, the race's decapitation
    /// art, and blood on the ground unless the race says none. Without race art the
    /// default dismember model stands in.
    public func showDismemberment(of key: ReferenceKey, node: String, at position: SIMD3<Float>) {
        let effects = game.effects
        let flags = race(of: key)?.flags ?? []
        let resolved = bodyParts(of: key)
        if
            !flags.contains(.noBloodSpray), let resolved,
            let part = resolved.record.part(onNode: node)?.nodeData,
            let explosion = effects.records.resolve(
                part.severableExplosion, fromPlugin: resolved.sourcePlugin
            )
        {
            game.effectsWorld.detonateEffectExplosion(explosion, at: position)
        }
        let art = race(of: key).flatMap { race in
            loadOrderPlugin.flatMap {
                effects.records.resolve(race.details.decapitationEffect, fromPlugin: $0)
            }
        }
        let attached = art.map {
            effects.attach($0, to: .actor(key), cause: .race, duration: nil) != nil
        } ?? false
        if !attached {
            effects.showDismemberParticle(at: position)
        }
        if !flags.contains(.noBloodDecal) {
            effects.showDefaultBlood(on: key, at: position, melee: true)
        }
    }

    public func isCorpseKept(_ key: ReferenceKey) -> Bool {
        game.scripts.bridge?.questRuntime?.aliasResolution().holds(key) ?? true
    }

    public func removeCorpse(_ key: ReferenceKey) {
        _ = game.scripts.bridge?.write(ReferenceDeletionState.deleted.erased, for: key)
    }

    private var loadOrderPlugin: String? {
        game.worldData?.actorValueBaselines?.resolver?.pluginName
    }

    private func race(of key: ReferenceKey) -> Race? {
        guard
            let race = game.menuWorld.race(of: key),
            let races = game.worldData?.actorValueBaselines?.resolver?.races
        else { return nil }
        return races[race.rawValue]
    }

    private func bodyParts(of key: ReferenceKey) -> ResolvedRecord<BodyPartData>? {
        guard let race = race(of: key), let plugin = loadOrderPlugin else { return nil }
        return game.worldData?.presentationRecords?.bodyParts
            .resolve(race.details.bodyPartData, fromPlugin: plugin)
    }
}
