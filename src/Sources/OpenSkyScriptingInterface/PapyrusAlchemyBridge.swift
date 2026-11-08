import Foundation
public import OpenSkyFormatsESM

/// What the alchemy natives ask of the inventory feature.
public protocol PapyrusAlchemyBridge: AnyObject {
    /// Teaches `indices` of `ingredient`, or every effect when nil. False for a
    /// form that is no ingredient.
    func learnIngredientEffects(_ ingredient: FormID, indices: [Int]?) -> Bool
    /// The index learnt, -1 when every effect is known, nil for no ingredient.
    func learnNextIngredientEffect(_ ingredient: FormID) -> Int?
    /// Nil for a form that is neither a potion nor an ingredient.
    func isHostileItem(_ item: FormID) -> Bool?
}
