// `openskycli game state objects`: the object behaviour graphs that run now, such as a
// swinging blade's, so a check can see a trap move (docs/engine/object-animation.md).

import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyObjectAnimation
import simd

extension AgentWorldAdapter {
    /// Every running graph, or one with its bone positions in the object's own space.
    func objectsState(reference: String?) throws(AgentFailure) -> AgentJSON {
        let objects = game.objectAnimationWorld.objects
        guard let reference else {
            return ["objects": .array(objects.rows.map(Self.json))]
        }
        let target = try resolveReference(reference)
        guard let row = objects.rows.first(where: { $0.reference == target.formID.rawValue }) else {
            throw AgentFailure(.notFound, "that reference runs no object graph")
        }
        var fields = Self.fields(row)
        let bones = objects.boneMatrices(of: row.reference) ?? []
        fields["bones"] = .array(bones.map(Self.bone))
        return .object(fields)
    }

    /// A swing turns a bone about its own origin, so the rotation shows it.
    private static func bone(_ matrix: simd_float4x4) -> AgentJSON {
        let rotation = simd_quatf(simd_float3x3(
            SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        ))
        return [
            "position": .init(SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)),
            "rotationDegrees": .init(rotation.angle * 180 / .pi)
        ]
    }

    private static func json(_ row: ObjectAnimationRow) -> AgentJSON {
        .object(fields(row))
    }

    private static func fields(_ row: ObjectAnimationRow) -> [String: AgentJSON] {
        [
            "ref": .formID(row.reference),
            "project": .string(row.project),
            "state": .init(row.activeState),
            "states": .array(row.activeStates.map { .string($0) }),
            "waitingForClip": .bool(row.isWaitingForClip),
            "events": .array(row.events.map { .string($0) })
        ]
    }
}

extension AgentWorldAdapter {
    /// Every running effect graph, or those on one actor (docs/engine/effect-graphs.md),
    /// and every effect model drawn as its own posed copy.
    func effectsState(reference: String?) throws(AgentFailure) -> AgentJSON {
        var rows = game.effectGraphs.rows
        if let reference {
            let target = try resolveReference(reference)
            rows = rows.filter { $0.actor == target.key }
        }
        let posed = game.effectModelPoser.rows.map { row -> AgentJSON in
            [
                "effect": .init(row.effectID),
                "model": .string(row.modelPath),
                "bones": .array(row.bones.map { .string($0) })
            ]
        }
        return ["posed": .array(posed), "effects": .array(rows.map { row in
            [
                "effect": .init(row.effectID),
                "actor": .string("\(row.actor)"),
                "name": .string(row.effectName),
                "project": .string(row.project),
                "state": .init(row.activeState),
                "lastEvent": .init(row.lastEvent),
                "eventsTaken": .init(row.takenCount)
            ]
        })]
    }
}
