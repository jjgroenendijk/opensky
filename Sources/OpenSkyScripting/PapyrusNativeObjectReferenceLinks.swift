// Activation and linked-reference natives of the `ObjectReference` family: the
// parts of a lever-opens-a-door script. The policy is the one stated in
// `PapyrusNativeObjectReference.swift`.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// `bool Activate(ObjectReference akActivator, bool abDefaultProcessingOnly = false)`.
    /// Its whole effect is `PapyrusWorldBridge.activate(_:by:togglesOpen:)`, with
    /// `togglesOpen` false: a script activation is not an open action. The
    /// activator falls back to the player when absent or `None`. Returns false only
    /// when the recursion cap refuses the activation.
    public static func installActivate(into registry: inout PapyrusNativeRegistry) {
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

    /// `ObjectReference GetLinkedRef(Keyword apKeyword = None)`. With a keyword it
    /// returns the first XLKR link tagged with it; with `None`, the first untagged
    /// link. Every missing answer is `None`. Only a wrong argument type fails,
    /// because that is a broken call rather than an absent link.
    public static func installLinkedReference(into registry: inout PapyrusNativeRegistry) {
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
        world: any PapyrusWorldBridge
    ) -> PapyrusValue {
        guard
            let placed = world.placedReference(for: key),
            let link = linkedReference(in: placed, keyword: keyword, world: world),
            let linkedKey = world.referenceKey(forFormID: link),
            let handle = world.objectHandle(for: linkedKey)
        else { return .none }
        return .object(handle)
    }

    /// The linked reference's FormID, matched by keyword. XLKR stores the keyword
    /// as a load-order-relative FormID, so each tag resolves to a `ReferenceKey`
    /// before the compare. A tag that does not resolve never matches.
    private static func linkedReference(
        in placed: PlacedReference,
        keyword: ReferenceKey?,
        world: any PapyrusWorldBridge
    ) -> FormID? {
        guard let keyword else { return placed.linkedReference() }
        return placed.linkedReferences.first { link in
            guard let tag = link.keyword else { return false }
            return world.referenceKey(forFormID: tag) == keyword
        }?.ref
    }
}
