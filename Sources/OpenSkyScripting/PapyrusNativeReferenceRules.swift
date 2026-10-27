// Reference, cell, faction, and topic natives the app answers: model nodes, impact
// effects, forced ragdolls, `Cell.Reset`, the stolen-item values, and `Topic.Add`.
// See docs/engine/papyrus-world.md#session-natives.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState
import simd

extension PapyrusNativeFunctions {
    static let stolenValueCrimeName = "stolenValueCrime"
    static let stolenValueNoCrimeName = "stolenValueNoCrime"

    static func installReferenceRules(into registry: inout PapyrusNativeRegistry) {
        installNodes(into: &registry)
        // "Flags this cell for reset on next load", even in a no-reset zone.
        scriptState("Cell", "Reset", into: &registry) { call, bridge, key in
            guard let reset = bridge.gameNatives.resetCell else {
                return failure(call, "Reset needs the running game")
            }
            return reset(key) ? .returned(.none) : failure(call, "Reset found no such cell")
        }
        scriptState(
            "ObjectReference",
            "ForceAddRagdollToWorld",
            into: &registry
        ) { call, bridge, key in
            guard let ragdoll = bridge.gameNatives.forceRagdoll else {
                return failure(call, "ForceAddRagdollToWorld needs the running game")
            }
            _ = ragdoll(key)
            return .returned(.none)
        }
        // The node, pick direction, and rotation arguments are not read: the impact
        // plays where the reference stands.
        // `PlayImpactEffect(ImpactDataSet, string asNodeName = "", float afPickDirX = 0.0,
        // afPickDirY = 0.0, afPickDirZ = -1.0, afPickLength = 512.0,
        // bool abApplyNodeRotation = false, bool abUseNodeLocalRotation = false)`.
        scriptState("ObjectReference", "PlayImpactEffect", into: &registry) { call, bridge, key in
            guard
                let impacts = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                let play = bridge.gameNatives.playImpact
            else { return failure(call, "PlayImpactEffect needs an impact data set") }
            let pick = PapyrusImpactPick(
                source: key, node: string(call, at: 1) ?? "",
                direction: SIMD3(
                    float(call, at: 2) ?? 0, float(call, at: 3) ?? 0, float(call, at: 4) ?? -1
                ),
                length: float(call, at: 5) ?? 512,
                appliesNodeRotation: boolean(call, at: 6, default: false),
                usesNodeLocalRotation: boolean(call, at: 7, default: false)
            )
            return .returned(.boolean(play(impacts, pick)))
        }
        for (name, valueName) in [
            ("GetStolenItemValueCrime", stolenValueCrimeName),
            ("GetStolenItemValueNoCrime", stolenValueNoCrimeName)
        ] {
            scriptState("Faction", name, into: &registry) { _, bridge, key in
                let value = bridge.scriptedState(of: key).value(valueName) ?? 0
                return .returned(.integer(Int32(clamping: Int64(value))))
            }
        }
        // OpenSky offers every topic whose conditions pass, so a known flag is all `Add` sets.
        scriptState("Topic", "Add", into: &registry) { _, bridge, key in
            bridge.updateScriptedState(of: key) { $0.setFlag("topicAdded", true) }
            return .returned(.none)
        }
    }

    /// `bool HasNode(string asNodeName)` and `MoveToNode(ObjectReference akTarget, string
    /// asNodeName)`, which takes the node's position and rotation. A model still loading
    /// answers once it has loaded.
    private static func installNodes(into registry: inout PapyrusNativeRegistry) {
        scriptState("ObjectReference", "HasNode", into: &registry) { call, bridge, key in
            guard let name = string(call, at: 0), let lookup = bridge.gameNatives.nodeTransform
            else { return failure(call, "HasNode needs a node name") }
            switch lookup(key, name, { .boolean($0 != nil) }) {
            case .found: return .returned(.boolean(true))
            case .missing: return .returned(.boolean(false))
            case let .loading(token): return .suspended(.external(token))
            }
        }
        scriptState("ObjectReference", "MoveToNode", into: &registry) { call, bridge, key in
            guard
                let target = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                let name = string(call, at: 1), let lookup = bridge.gameNatives.nodeTransform
            else { return failure(call, "MoveToNode needs a target and a node name") }
            let move = { [weak bridge] (node: simd_float4x4?) -> PapyrusValue in
                if let node, let bridge {
                    bridge.move(key, to: node)
                }
                return .none
            }
            switch lookup(target, name, move) {
            case let .found(node):
                bridge.move(key, to: node)
                return .returned(.none)
            case .missing: return failure(call, "MoveToNode found no node \(name)")
            case let .loading(token): return .suspended(.external(token))
            }
        }
    }
}

extension PapyrusWorldStateBridge {
    /// The player stole `value` from `faction`, seen or unseen.
    public func noteStolenValue(_ value: Int64, from faction: ReferenceKey, witnessed: Bool) {
        let name = witnessed
            ? PapyrusNativeFunctions.stolenValueCrimeName
            : PapyrusNativeFunctions.stolenValueNoCrimeName
        updateScriptedState(of: faction) { state in
            state.setValue(name, (state.value(name) ?? 0) + Float(value))
        }
    }

    /// Places `key` at a node's position and rotation, keeping its scale.
    func move(_ key: ReferenceKey, to node: simd_float4x4) {
        guard let state = referenceState(for: key) else { return }
        let basis = simd_float3x3(
            simd_normalize(SIMD3(node.columns.0.x, node.columns.0.y, node.columns.0.z)),
            simd_normalize(SIMD3(node.columns.1.x, node.columns.1.y, node.columns.1.z)),
            simd_normalize(SIMD3(node.columns.2.x, node.columns.2.y, node.columns.2.z))
        )
        write(ReferenceTransformOverride(
            position: SIMD3(node.columns.3.x, node.columns.3.y, node.columns.3.z),
            rotation: MatrixMath.eulerAngles(of: simd_quatf(basis)),
            scale: state.transform.scale
        ).erased, for: key)
    }

    /// Places `key` at `point`, keeping its rotation and scale.
    func move(_ key: ReferenceKey, to point: SIMD3<Float>) {
        guard let state = referenceState(for: key) else { return }
        write(ReferenceTransformOverride(
            position: point, rotation: state.transform.rotation, scale: state.transform.scale
        ).erased, for: key)
    }
}
