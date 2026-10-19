// `Ingredient` and `Potion` natives: which effects the player knows, and whether the
// item is hostile. Creation Kit wiki "Ingredient Script":
// <https://ck.uesp.net/wiki/Ingredient_Script>. See docs/engine/alchemy.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

/// What the alchemy natives ask of the inventory feature.
@MainActor
public protocol PapyrusAlchemyBridge: AnyObject {
    /// Teaches `indices` of `ingredient`, or every effect when nil. False for a
    /// form that is no ingredient.
    func learnIngredientEffects(_ ingredient: FormID, indices: [Int]?) -> Bool
    /// The index learnt, -1 when every effect is known, nil for no ingredient.
    func learnNextIngredientEffect(_ ingredient: FormID) -> Int?
    /// Nil for a form that is neither a potion nor an ingredient.
    func isHostileItem(_ item: FormID) -> Bool?
}

extension PapyrusNativeFunctions {
    static func installAlchemy(into registry: inout PapyrusNativeRegistry) {
        for script in ["Ingredient", "Potion"] {
            onItemForm(script, "IsHostile", into: &registry) { call, bridge, item in
                guard let hostile = bridge.isHostileItem(item) else {
                    return failure(call, "IsHostile needs a potion or an ingredient")
                }
                return .returned(.boolean(hostile))
            }
        }
        onItemForm("Ingredient", "LearnEffect", into: &registry) { call, bridge, item in
            let index = integer(call, at: 0).map { [Int($0)] } ?? []
            return bridge.learnIngredientEffects(item, indices: index)
                ? .returned(.none) : failure(call, "LearnEffect needs an ingredient")
        }
        onItemForm("Ingredient", "LearnAllEffects", into: &registry) { call, bridge, item in
            bridge.learnIngredientEffects(item, indices: nil)
                ? .returned(.none) : failure(call, "LearnAllEffects needs an ingredient")
        }
        onItemForm("Ingredient", "LearnNextEffect", into: &registry) { call, bridge, item in
            guard let index = bridge.learnNextIngredientEffect(item) else {
                return failure(call, "LearnNextEffect needs an ingredient")
            }
            return .returned(.integer(Int32(index)))
        }
    }

    /// A native called on an item form, which resolves to its load-order FormID.
    private static func onItemForm(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (PapyrusNativeCall, any PapyrusAlchemyBridge, FormID)
            -> PapyrusNativeResult
    ) {
        let native = PapyrusNativeFunction(
            scriptName: script, functionName: name
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let bridge = world.alchemy,
                case let .plugin(plugin, objectID)? = call.receiver
                    .flatMap(world.referenceKey(for:)),
                let item = world.formIDResolver?.localFormID(
                    of: ResolvedFormID(plugin: plugin, objectID: objectID)
                )
            else { return failure(call, "\(name) needs the alchemy bridge and a form") }
            return body(call, bridge, item)
        }
        registry.register(native)
    }
}
