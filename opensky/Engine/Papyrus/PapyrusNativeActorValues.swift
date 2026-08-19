// The three actor-value *write* natives (issue #496, roadmap item 20.3):
// `SetActorValue`, `ModActorValue` and `ForceActorValue`.
//
// A satellite of `PapyrusNativeActor.swift` rather than more of it, following
// the split rule the renderer passes and `ActorValueRuntimeGeneral` already
// follow: that file holds the reads, the status flags and the combat calls.
//
// All three were deliberately unregistered through M19, and the reason was
// stated in that file's header: the three primaries had no base-plus-modifier
// store, so `SetActorValue("Health", 200)` could only have moved current health
// and a script that meant to buff an NPC's maximum would have appeared to work.
// Item 20.3 gives the primaries the same store the other 161 values have, so the
// reason is gone and the natives are registered.
//
// Semantics are quoted from the Creation Kit wiki at each registration and
// implemented in `ActorValueRuntimeGeneral.swift`; the split between the two is
// the same one every other native family keeps — the registration validates
// arguments and reports failures, the runtime decides what a slot means.
//
// Documented in docs/engine/actor-values.md and docs/engine/papyrus-vm.md.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    /// `SetActorValue(string, float)`, `ModActorValue(string, float)` and
    /// `ForceActorValue(string, float)`.
    ///
    /// "Sets the base value specified actor value on the actor to the passed-in
    /// value. Any modifiers are left intact."
    /// (<https://ck.uesp.net/wiki/SetActorValue_-_Actor>)
    ///
    /// "Modifies the specified actor value on the actor ... ModActorValue is
    /// distinct from DamageActorValue because it adjusts the maximum value for
    /// the AV, while DamageActorValue or RestoreActorValue only adjust the
    /// current value. For example, if an actor has 100 Health, ModActorValue by
    /// -10 will lower the health total to 90/90, whereas DamageActorValue by 10
    /// will result in 90/100 Health."
    /// (<https://ck.uesp.net/wiki/ModActorValue_-_Actor>)
    ///
    /// "Forces the specified actor value to the passed-in value ... this
    /// function modifies the 'permanent modifier' described in the Actor Value
    /// documentation, and that affects how the current value is computed."
    /// (<https://ck.uesp.net/wiki/ForceActorValue_-_Actor>)
    ///
    /// `SetAV`, `ModAV` and `ForceAV` are Papyrus-level wrappers around these
    /// three, so they need no registration of their own — the same rule
    /// `GetAV` and `DamageAV` already follow.
    ///
    /// A negative argument is passed through rather than taken as a magnitude,
    /// which is the opposite of what `DamageActorValue` does and is deliberate:
    /// the wiki's own example modifies health by -10, and a `ModActorValue` that
    /// could only ever raise a value would be a different function.
    static func installActorValueWriteNatives(into registry: inout PapyrusNativeRegistry) {
        for write in PapyrusActorValueWrite.allCases {
            registry.register(PapyrusNativeFunction(
                scriptName: "Actor",
                functionName: write.rawValue
            ) { call, context in
                guard let actor = actorTarget(call, context) else {
                    return needsActor(call)
                }
                guard let index = actorValueIndex(call, at: 0) else {
                    return unknownActorValue(call, at: 0)
                }
                guard let value = float(call, at: 1), value.isFinite else {
                    return failure(call, "\(write.rawValue) needs a finite value")
                }
                guard
                    actor.world.writeActorValue(write, at: index, to: value, on: actor.key) != nil
                else {
                    return needsActor(call)
                }
                return .returned(.none)
            })
        }
    }
}
