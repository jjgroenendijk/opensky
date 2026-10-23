// The Ingredient and Potion natives reach the alchemy bridge with the item's
// load-order FormID, and fail without a bridge or for a form that is no item.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
final class FakeAlchemyBridge: PapyrusAlchemyBridge {
    var ingredients: Set<FormID> = []
    var hostile: [FormID: Bool] = [:]
    private(set) var learnt: [String] = []
    var next = 2

    func learnIngredientEffects(_ ingredient: FormID, indices: [Int]?) -> Bool {
        guard ingredients.contains(ingredient) else { return false }
        learnt.append(indices.map { "\($0)" } ?? "all")
        return true
    }

    func learnNextIngredientEffect(_ ingredient: FormID) -> Int? {
        ingredients.contains(ingredient) ? next : nil
    }

    func isHostileItem(_ item: FormID) -> Bool? {
        hostile[item]
    }
}

@MainActor
struct PapyrusNativeAlchemyTests {
    private static let ingredientID: UInt32 = 0x0000_0EEE

    @MainActor
    private struct Harness {
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
        let alchemy: FakeAlchemyBridge
        let item: FormID

        func call(
            _ script: String, _ name: String, arguments: [PapyrusValue] = [],
            returnType: PapyrusType = .none
        ) -> PapyrusNativeResult {
            let key = ReferenceKey.plugin(
                name: PapyrusWorldFixture.pluginName, objectID: ingredientID
            )
            return registry.invoke(PapyrusWorldFixture.methodCall(
                script, name, receiver: session.world.objectHandle(for: key),
                arguments: arguments, returnType: returnType
            ))
        }
    }

    private static func harness(bridged: Bool = true) throws -> Harness {
        let fixture = try PapyrusNativeReferenceFixture.make()
        fixture.session.bridge.formIDResolver = PapyrusWorldFixture.resolver
        let alchemy = FakeAlchemyBridge()
        let item = try #require(PapyrusWorldFixture.resolver.localFormID(
            of: ResolvedFormID(plugin: PapyrusWorldFixture.pluginName, objectID: ingredientID)
        ))
        alchemy.ingredients = [item]
        alchemy.hostile[item] = true
        if bridged {
            fixture.session.bridge.alchemy = alchemy
        }
        return Harness(
            session: fixture.session, registry: fixture.registry, alchemy: alchemy, item: item
        )
    }

    @Test func learningNativesTeachTheIngredient() throws {
        let harness = try Self.harness()
        #expect(harness.call("Ingredient", "LearnEffect", arguments: [.integer(1)])
            == .returned(.none))
        #expect(harness.call("Ingredient", "LearnAllEffects") == .returned(.none))
        #expect(harness.call("Ingredient", "LearnNextEffect", returnType: .integer)
            == .returned(.integer(2)))
        #expect(harness.alchemy.learnt == ["[1]", "all"])
    }

    @Test func isHostileAnswersForBothScripts() throws {
        let harness = try Self.harness()
        for script in ["Ingredient", "Potion"] {
            #expect(harness.call(script, "IsHostile", returnType: .boolean)
                == .returned(.boolean(true)))
        }
        harness.alchemy.hostile = [:]
        #expect(harness.call("Potion", "IsHostile", returnType: .boolean) != .returned(.none))
    }

    @Test func withoutTheBridgeANativeFails() throws {
        let harness = try Self.harness(bridged: false)
        #expect(harness.call("Ingredient", "LearnAllEffects") != .returned(.none))
    }
}
