// The destruction natives over `DestructionProgress`: `DamageObject`, `SetDestroyed`,
// `ClearDestruction`, and `GetCurrentDestructionStage`, with `OnDestructionStageChanged`
// on a stage change. Signatures are from <https://ck.uesp.net/wiki/ObjectReference_Script>.
// See docs/engine/papyrus-destruction.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    static func installDestruction(into registry: inout PapyrusNativeRegistry) {
        // `DamageObject(float afDamage)`. An object with no `DEST` data takes no damage.
        scriptState("ObjectReference", "DamageObject", into: &registry) { call, bridge, key in
            guard let amount = float(call, at: 0), amount.isFinite else {
                return failure(call, "DamageObject needs a finite number")
            }
            guard let data = bridge.destructibleData(of: key) else { return .returned(.none) }
            var progress = bridge.destruction(of: key)
            if progress.apply(damage: amount, to: data) {
                bridge.write(ReferenceEnableState.disabled.erased, for: key)
            }
            bridge.storeDestruction(progress, of: key)
            return .returned(.none)
        }
        // `SetDestroyed(bool abDestroyed = true)`.
        scriptState("ObjectReference", "SetDestroyed", into: &registry) { call, bridge, key in
            let progress = DestructionProgress.destroyed(
                boolean(call, at: 0, default: true), data: bridge.destructibleData(of: key)
            )
            bridge.storeDestruction(progress, of: key)
            return .returned(.none)
        }
        scriptState("ObjectReference", "ClearDestruction", into: &registry) { _, bridge, key in
            bridge.storeDestruction(DestructionProgress(), of: key)
            return .returned(.none)
        }
        scriptState(
            "ObjectReference", "GetCurrentDestructionStage", into: &registry
        ) { _, bridge, key in
            .returned(.integer(Int32(bridge.destruction(of: key).stage)))
        }
    }
}

extension PapyrusWorldStateBridge {
    /// The `DEST` data of the reference's base, read in its plugin's space.
    func destructibleData(of key: ReferenceKey) -> Destructible? {
        guard let keywordStore, let base = baseObject(of: key) else { return nil }
        let space = if case let .plugin(plugin, _) = key {
            plugin
        } else {
            FormIDResolver.loadOrderSpaceName
        }
        return keywordStore.resolvedID(base, fromPlugin: space)
            .flatMap(keywordStore.destructible(of:))
    }

    func destruction(of key: ReferenceKey) -> DestructionProgress {
        let state = scriptedState(of: key)
        return DestructionProgress(
            damage: state.value(ScriptedStateName.destructionDamage) ?? 0,
            stage: Int(state.value(ScriptedStateName.destructionStage) ?? 0),
            isDestroyed: state.flag(ScriptedStateName.destroyed) == true
        )
    }

    /// Stores `progress` and queues `OnDestructionStageChanged(aiOldStage,
    /// aiCurrentStage)` when the stage moved. An intact object keeps no state.
    func storeDestruction(_ progress: DestructionProgress, of key: ReferenceKey) {
        let old = destruction(of: key).stage
        updateScriptedState(of: key) { state in
            state.setValue(
                ScriptedStateName.destructionDamage,
                progress.damage > 0
                    ? progress.damage : nil
            )
            state.setValue(
                ScriptedStateName.destructionStage,
                progress.stage > 0
                    ? Float(progress.stage) : nil
            )
            state.setFlag(ScriptedStateName.destroyed, progress.isDestroyed ? true : nil)
        }
        guard old != progress.stage, let world else { return }
        _ = queueReferenceEvent(
            PapyrusEngineEvents.onDestructionStageChanged, on: key,
            [.integer(Int32(old)), .integer(Int32(progress.stage))], in: world
        )
    }
}
