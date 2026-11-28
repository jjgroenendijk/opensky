// The body part a hit struck: the part of the race's `BPTD` whose node, in the actor's
// current pose, lies nearest the hit point. See docs/formats/body-parts.md#in-the-game.

import OpenSkyCombat
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkySessionInterface
import simd

extension CombatImpactEffectsAdapter {
    /// The part a hit at `point` struck. With no point the line from the attacker's torso
    /// decides: the part nearest that torso.
    public func struckBodyPart(
        of target: ReferenceKey, at point: SIMD3<Float>?, from attacker: ReferenceKey?
    ) -> StruckBodyPart? {
        guard let resolved = bodyParts(of: target) else { return nil }
        let placed = placements(of: target, parts: resolved.record)
        guard
            let aim = point ?? attacker.flatMap(torso(of:)),
            let hit = BodyPartHitRules.struckPart(placed.map(\.placement), at: aim),
            let part = placed.first(where: { $0.placement.partType == hit.partType })?.part,
            let node = part.nodeName, let data = part.nodeData
        else { return nil }
        let records = game.effects.records
        let bloodSet = records.resolve(
            data.severableImpactDataSet,
            fromPlugin: resolved.sourcePlugin
        )
        .flatMap { records.loadOrderFormID($0) }
        return StruckBodyPart(
            partType: data.partType, node: node, position: hit.position,
            damageMultiplier: data.damageMultiplier, healthPercent: data.healthPercent,
            actorValue: data.actorValue < 0 ? nil : Int32(data.actorValue),
            bloodImpactDataSet: bloodSet
        )
    }

    /// The first part of each type, where its node stands now. A body holds at most one
    /// part of a type, so a later one is never struck.
    private func placements(
        of key: ReferenceKey, parts: BodyPartData
    ) -> [(placement: BodyPartPlacement, part: BodyPart)] {
        let bones = Dictionary(
            game.effectsWorld.effectBones(of: key).map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen: Set<UInt8> = []
        return parts.parts.compactMap { part in
            guard
                let data = part.nodeData, let node = part.nodeName,
                let bone = bones[node.lowercased()], seen.insert(data.partType).inserted
            else { return nil }
            let position = SIMD3(bone.columns.3.x, bone.columns.3.y, bone.columns.3.z)
            return (
                BodyPartPlacement(
                    partType: data.partType, position: position, toHitChance: data.toHitChance
                ),
                part
            )
        }
    }

    private func torso(of key: ReferenceKey) -> SIMD3<Float>? {
        if
            let parts = bodyParts(of: key)?.record,
            let torso = placements(of: key, parts: parts)
                .first(where: { $0.placement.partType == 0 })
        {
            return torso.placement.position
        }
        // Without a torso part, the middle of the posed bones stands in.
        let bones = game.effectsWorld.effectBones(of: key).values
        guard !bones.isEmpty else { return nil }
        let sum = bones.reduce(SIMD3<Float>.zero) {
            $0 + SIMD3($1.columns.3.x, $1.columns.3.y, $1.columns.3.z)
        }
        return sum / Float(bones.count)
    }

    private func bodyParts(of key: ReferenceKey) -> ResolvedRecord<BodyPartData>? {
        guard
            let race = game.menuWorld.race(of: key),
            let resolver = game.combatRecords?.actorValueBaselines?.resolver,
            let record = resolver.races[race.rawValue]
        else { return nil }
        let plugin = resolver.pluginName
        return game.combatRecords?.presentationRecords?.bodyParts
            .resolve(record.details.bodyPartData, fromPlugin: plugin)
    }
}
