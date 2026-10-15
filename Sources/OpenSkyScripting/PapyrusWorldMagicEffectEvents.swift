// Magic effect events from the world-state journal: every active-effect write since the
// last frame, diffed old against new by application number. A new number is an effect
// that started; a lost one ended by expiry or dispel. See docs/engine/papyrus-magic-effects.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge {
    /// Queues `OnMagicEffectApply` on the target's scripts, and starts and finishes the
    /// effects' own scripts, for the active-effect writes since the last call. The first
    /// call only sets the cursor. Returns how many effects started or ended.
    @discardableResult
    public func queueMagicEffectEvents() -> Int {
        let next = worldState.nextJournalSequence
        defer { effectJournalCursor = next }
        guard let cursor = effectJournalCursor, cursor < next, let world else { return 0 }
        var changed = 0
        for entry in worldState.journalEntries(since: cursor) where entry.kind == .activeEffects {
            let old = Self.effects(in: entry.oldValue)
            let new = Self.effects(in: entry.newValue)
            let oldSequences = Set(old.map(\.sequence))
            let newSequences = Set(new.map(\.sequence))
            for effect in new where !oldSequences.contains(effect.sequence) {
                start(effect, on: entry.key, in: world)
                changed += 1
            }
            for effect in old where !newSequences.contains(effect.sequence) {
                world.finishEffectScripts(PapyrusActiveEffectID(
                    target: entry.key, sequence: effect.sequence
                ))
                changed += 1
            }
        }
        return changed
    }

    /// Starts the next read at the journal's end, so a load is not read as new effects.
    public func skipMagicEffectJournal() {
        effectJournalCursor = worldState.nextJournalSequence
    }

    private static func effects(in value: WorldStateComponentValue?) -> [ActiveEffect] {
        value.flatMap(ActiveEffectState.init(erased:))?.effects ?? []
    }

    private func start(
        _ effect: ActiveEffect,
        on target: ReferenceKey,
        in world: PapyrusWorldRuntime
    ) {
        queueMagicEffectApply(effect, on: target, in: world)
        guard
            let store = magicEffectStore,
            let record = store.effect(key: effect.effect),
            !record.effect.scriptData.scripts.isEmpty
        else { return }
        let resolver = store.sourceResolver(of: record)
            ?? formIDResolver
            ?? FormIDResolver(pluginName: record.sourcePlugin, masters: [])
        world.startEffectScripts(
            PapyrusActiveEffectRun(
                id: PapyrusActiveEffectID(target: target, sequence: effect.sequence),
                effect: effect.effect,
                caster: effect.caster
            ),
            scripts: record.effect.scriptData.scripts,
            formIDResolver: resolver
        )
    }

    /// `OnMagicEffectApply(ObjectReference akCaster, MagicEffect akEffect)` on the
    /// target's own scripts (<https://ck.uesp.net/wiki/OnMagicEffectApply_-_ObjectReference>).
    private func queueMagicEffectApply(
        _ effect: ActiveEffect, on target: ReferenceKey, in world: PapyrusWorldRuntime
    ) {
        let name = PapyrusEngineEvents.onMagicEffectApply
        let arguments: [PapyrusValue] = [
            effect.caster.map { .object(world.objectHandle(for: $0)) } ?? .none,
            .object(world.objectHandle(for: effect.effect))
        ]
        for key in world.instanceKeys(on: target) where world.handlesEvent(name, key: key) {
            world.enqueue(PapyrusScriptEvent(target: key, functionName: name, arguments: arguments))
        }
    }
}
