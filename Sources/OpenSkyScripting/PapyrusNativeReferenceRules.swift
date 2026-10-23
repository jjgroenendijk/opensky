// Reference, cell, faction, and topic natives the app answers: model nodes, impact
// effects, forced ragdolls, `Cell.Reset`, the stolen-item values, and `Topic.Add`.
// See docs/engine/papyrus-world.md#session-natives.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

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
        scriptState("ObjectReference", "PlayImpactEffect", into: &registry) { call, bridge, key in
            guard
                let impacts = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                let play = bridge.gameNatives.playImpact
            else { return failure(call, "PlayImpactEffect needs an impact data set") }
            return .returned(.boolean(play(impacts, key)))
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
    /// asNodeName)`. A model still loading answers once it has loaded.
    private static func installNodes(into registry: inout PapyrusNativeRegistry) {
        scriptState("ObjectReference", "HasNode", into: &registry) { call, bridge, key in
            guard let name = string(call, at: 0), let lookup = bridge.gameNatives.nodePosition
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
                let name = string(call, at: 1), let lookup = bridge.gameNatives.nodePosition
            else { return failure(call, "MoveToNode needs a target and a node name") }
            let move = { [weak bridge] (point: SIMD3<Float>?) -> PapyrusValue in
                if let point, let bridge {
                    bridge.move(key, to: point)
                }
                return .none
            }
            switch lookup(target, name, move) {
            case let .found(point):
                bridge.move(key, to: point)
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

    /// Places `key` at `point`, keeping its rotation and scale.
    func move(_ key: ReferenceKey, to point: SIMD3<Float>) {
        guard let state = referenceState(for: key) else { return }
        write(ReferenceTransformOverride(
            position: point, rotation: state.transform.rotation, scale: state.transform.scale
        ).erased, for: key)
    }
}
