// The destruction natives over `DestructionProgress`: `DamageObject`, `SetDestroyed`,
// `ClearDestruction`, and `GetCurrentDestructionStage`, with `OnDestructionStageChanged`
// on a stage change. Signatures are from <https://ck.uesp.net/wiki/ObjectReference_Script>.
// See docs/engine/papyrus-destruction.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldState
import simd

extension PapyrusNativeFunctions.DestructionNatives {
    static func installDestruction(into registry: inout PapyrusNativeRegistry) {
        // `DamageObject(float afDamage)`. An object with no `DEST` data takes no damage.
        scriptState("ObjectReference", "DamageObject", into: &registry) { call, bridge, key in
            guard let amount = float(call, at: 0), amount.isFinite else {
                return failure(call, "DamageObject needs a finite number")
            }
            bridge.referenceEvents.damageDestructible(key, amount: amount, forced: true)
            return .returned(.none)
        }
        // `SetDestroyed(bool abDestroyed = true)`.
        scriptState("ObjectReference", "SetDestroyed", into: &registry) { call, bridge, key in
            let progress = DestructionProgress.destroyed(
                boolean(call, at: 0, default: true),
                data: bridge.referenceEvents.destructibleData(of: key)
            )
            bridge.referenceEvents.storeDestruction(progress, of: key)
            return .returned(.none)
        }
        scriptState("ObjectReference", "ClearDestruction", into: &registry) { _, bridge, key in
            bridge.referenceEvents.storeDestruction(DestructionProgress(), of: key)
            return .returned(.none)
        }
        scriptState(
            "ObjectReference", "GetCurrentDestructionStage", into: &registry
        ) { _, bridge, key in
            .returned(.integer(Int32(bridge.referenceEvents.destruction(of: key).stage)))
        }
    }
}

extension PapyrusWorldStateBridge.ReferenceEvents {
    /// The `DEST` data of the reference's base, read in its plugin's space.
    func destructibleData(of key: ReferenceKey) -> Destructible? {
        destructibleBase(of: key)?.data
    }

    private func destructibleBase(
        of key: ReferenceKey
    ) -> (base: ResolvedFormID, data: Destructible)? {
        guard
            let keywordStore = bridge.stores.keywordStore,
            let base = bridge.baseObject(of: key) else { return nil }
        let space = if case let .plugin(plugin, _) = key {
            plugin
        } else {
            FormIDResolver.loadOrderSpaceName
        }
        guard
            let resolved = keywordStore.resolvedID(base, fromPlugin: space),
            let data = keywordStore.destructible(of: resolved)
        else { return nil }
        return (resolved, data)
    }

    /// Damages `key` through its stages. A disabled or deleted reference takes none.
    /// The stages passed are queued for the session. False when it has no `DEST` data.
    @discardableResult
    func damageDestructible(_ key: ReferenceKey, amount: Float, forced: Bool) -> Bool {
        guard let (base, data) = destructibleBase(of: key) else { return false }
        guard bridge.referenceState(for: key)?.isVisible != false else { return true }
        var progress = destruction(of: key)
        let passed = progress.apply(damage: amount, to: data, forced: forced)
        storeDestruction(progress, of: key)
        guard !passed.isEmpty else { return true }
        if passed.contains(where: { $0.flags & DestructionProgress.disable != 0 }) {
            bridge.write(ReferenceEnableState.disabled.erased, for: key)
        }
        let resolve = { (id: FormID?) in
            id.flatMap { bridge.stores.keywordStore?.resolvedID($0, fromPlugin: base.plugin) }
                .map(ReferenceKey.init(resolved:))
        }
        var change = DestructionStageChange(
            reference: key,
            stages: passed.map { stage in
                var change = DestructionStageChange.Stage(
                    index: stage.index, model: stage.model?.path,
                    selfDamagePerSecond: Float(stage.selfDamagePerSecond),
                    explosion: resolve(stage.explosion), debris: resolve(stage.debris),
                    debrisCount: Int(stage.debrisCount)
                )
                change.modelDamageStage = Int(stage.modelDamageStage)
                return change
            }
        )
        if let bounds = bridge.stores.keywordStore?.bounds(of: base), !bounds.isEmpty {
            let low = SIMD3<Float>(bounds.minimum)
            let high = SIMD3<Float>(bounds.maximum)
            change.boundsCentre = (low + high) / 2
            change.boundRadius = simd_length(high - low) / 2
        }
        bridge.runState.destructionChanges.append(change)
        return true
    }

    func destruction(of key: ReferenceKey) -> DestructionProgress {
        let state = bridge.scriptedState(of: key)
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
        bridge.updateScriptedState(of: key) { state in
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
        guard old != progress.stage, let world = bridge.world else { return }
        _ = queueReferenceEvent(
            PapyrusEngineEvents.onDestructionStageChanged, on: key,
            [.integer(Int32(old)), .integer(Int32(progress.stage))], in: world
        )
    }
}
