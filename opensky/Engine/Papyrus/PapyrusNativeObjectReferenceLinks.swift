// Activation and linked-reference natives of the `ObjectReference` family
// (issue #172). Satellite of `PapyrusNativeObjectReference.swift`, which states
// the policy these follow.
//
// These two are what a lever-opens-a-door script is made of: `GetLinkedRef`
// names the target the lever was authored against, and `Activate` is how a
// script activates something without the player pointing at it.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    /// `bool Activate(ObjectReference akActivator, bool abDefaultProcessingOnly = false)`.
    ///
    /// The whole world effect is `PapyrusWorldAccess.activate(_:by:togglesOpen:)`:
    /// one `ReferenceActivationState` write on the receiver and one
    /// `OnActivate` queued per script attached to it. It deliberately does not
    /// re-run the interaction raycast, does not move a door, and does not
    /// consult what the player is looking at.
    ///
    /// Three stated simplifications:
    ///
    /// * `abDefaultProcessingOnly` is accepted and ignored. It asks the engine
    ///   to skip script processing and run only the built-in behavior, and
    ///   OpenSky has no built-in activation behavior on this path to run.
    /// * `togglesOpen` is always false. The player's use key knows the
    ///   interaction is an `open` action and sets it; a script-side `Activate`
    ///   has no such action behind it, so it records the activation without
    ///   claiming the target opened.
    /// * The activator is argument 0, falling back to the player when the
    ///   argument is absent, is Papyrus `None`, or names a handle with no world
    ///   identity. An argument of some other type is a failure.
    ///
    /// Returns true unless the recursion cap refused the activation, which is
    /// the only way this can fail outright.
    static func installActivate(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: "Activate"
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return needsWorld(call)
            }
            var activator = target.world.playerKey
            if call.arguments.indices.contains(0) {
                switch call.arguments[0] {
                case .none:
                    break
                case let .object(handle):
                    activator = target.world.referenceKey(for: handle) ?? activator
                default:
                    return failure(call, "Activate needs an ObjectReference activator")
                }
            }
            let outcome = target.world.activate(
                target.key, by: activator, togglesOpen: false
            )
            return .returned(.boolean(!outcome.cappedByRecursion))
        })
    }

    /// `ObjectReference GetLinkedRef(Keyword apKeyword = None)`.
    ///
    /// Resolves through the REFR's decoded XLKR list: with a keyword, the first
    /// link tagged with it; with `None` — the Papyrus default — the first link
    /// that carries no keyword at all.
    ///
    /// Every "no answer" case returns Papyrus `None`, which is
    /// `PapyrusValue.none`, the same value the interpreter would write for a
    /// failed object-returning call: no decoded record behind the receiver, no
    /// matching link, a link pointing at a reference this session cannot name,
    /// or a keyword handle the world runtime never handed out. Only an argument
    /// of the wrong type is a failure, because that is a broken call rather
    /// than an absent link.
    static func installLinkedReference(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: "GetLinkedRef"
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return needsWorld(call)
            }
            var keyword: ReferenceKey?
            if call.arguments.indices.contains(0) {
                switch call.arguments[0] {
                case .none:
                    break
                case let .object(handle):
                    guard let key = target.world.referenceKey(for: handle) else {
                        return .returned(.none)
                    }
                    keyword = key
                default:
                    return failure(call, "GetLinkedRef needs a Keyword or None")
                }
            }
            return .returned(linkedReferenceValue(
                of: target.key, keyword: keyword, world: target.world
            ))
        })
    }

    /// The `PapyrusValue` `GetLinkedRef` answers with, once the keyword
    /// argument has been reduced to world identity.
    private static func linkedReferenceValue(
        of key: ReferenceKey,
        keyword: ReferenceKey?,
        world: PapyrusWorldAccess
    ) -> PapyrusValue {
        guard
            let placed = world.placedReference(for: key),
            let link = linkedReference(in: placed, keyword: keyword, world: world),
            let linkedKey = world.referenceKey(forFormID: link),
            let handle = world.objectHandle(for: linkedKey)
        else { return .none }
        return .object(handle)
    }

    /// The linked reference's FormID, matched by keyword.
    ///
    /// An untagged lookup is `PlacedReference.linkedReference(keyword:)`'s own
    /// default. A tagged one cannot be: XLKR stores the keyword as a
    /// load-order-relative FormID while the argument arrives as world identity,
    /// so each candidate tag is resolved to a `ReferenceKey` and compared
    /// there. A tag that does not resolve simply never matches, which keeps a
    /// mod whose keyword this session cannot name from matching everything.
    private static func linkedReference(
        in placed: PlacedReference,
        keyword: ReferenceKey?,
        world: PapyrusWorldAccess
    ) -> FormID? {
        guard let keyword else { return placed.linkedReference() }
        return placed.linkedReferences.first { link in
            guard let tag = link.keyword else { return false }
            return world.referenceKey(forFormID: tag) == keyword
        }?.ref
    }
}
