// The death effects' session half: the weapon that falls from a dead hand, the head
// a blow cuts off with its blood, and the bodies the excess-dead rule removes
// (docs/engine/ragdoll.md#death-effects).

import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyCombat
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension RagdollWorldAdapter {
    /// A dropped weapon rests this far above the feet, so it does not sink into the floor.
    static let droppedWeaponLift: Float = 4
    /// `BPND` part type 1 is the head (CK wiki "Skyrim bodyparts number").
    static let headPartType: UInt8 = 1
    /// `BPND` flag 0x01: the part can be severed.
    static let severableFlag: UInt8 = 0x01

    /// Only a drawn weapon falls; a sheathed one stays on the belt.
    func dropWeapon(of key: ReferenceKey) -> [String] {
        guard
            game.actorPlayback(for: key)?.weaponsDrawn == true,
            let streamer = game.streamer,
            let holder = streamer.inventoryHolder(of: key),
            let actor = streamer.referenceEntry(key: key)?.placedActor,
            let cell = streamer.cellLocation(of: key)
        else { return [] }
        let feet = actor.placement.position
        var position = feet
        if
            let pose = ragdollPose(of: key),
            let hand = game.animatedPose(for: key)?[ActorAttachmentBone.drawnWeapon]
        {
            let world = pose.actorToWorld * hand.columns.3
            position = SIMD3(world.x, world.y, feet.z)
        }
        position.z += Self.droppedWeaponLift
        guard
            let weapon = game.inventory.dropWeapon(
                of: holder,
                at: DropPlacement(location: cell, position: position, rotation: .zero)
            )
        else { return [] }
        let type = game.inventory.equipment?.catalog.item(weapon)?.animationType
        return [ActorAttachmentBone.drawnWeapon] + [ActorAttachmentBone.sheathNode(for: type)]
            .compactMap(\.self)
    }

    /// The head part of the race's `BPTD`: part type 1, or a part marked severable.
    func severableNode(of key: ReferenceKey) -> String? {
        guard let parts = bodyParts(of: key)?.record.parts else { return nil }
        let head = parts.first { $0.nodeData?.partType == Self.headPartType }
            ?? parts.first { ($0.nodeData?.flags ?? 0) & Self.severableFlag != 0 }
        return head?.nodeName
    }

    /// The race's own cut: the part's severable explosion, the race's decapitation
    /// art, and blood on the ground unless the race says none. Without race art the
    /// default dismember model stands in.
    func showDismemberment(of key: ReferenceKey, node: String, at position: SIMD3<Float>) {
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

    func isCorpseKept(_ key: ReferenceKey) -> Bool {
        game.scripts.bridge?.questRuntime?.aliasResolution().holds(key) ?? true
    }

    func removeCorpse(_ key: ReferenceKey) {
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
