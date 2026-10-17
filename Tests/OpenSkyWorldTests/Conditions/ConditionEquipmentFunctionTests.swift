// The equipment condition functions read `ActorEquipmentFacts`: hand types, the
// right-hand weapon, and worn keywords. An actor without equipment fails with a reason.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
@testable import OpenSkyWorld
import Testing

struct ConditionEquipmentFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let helmetKeyword: UInt32 = 0x6C0EC
    private static let cuirassKeyword: UInt32 = 0x6C0ED

    private static let armed = ActorEquipmentFacts(
        leftHandType: 10,
        rightHandType: 1,
        rightWeapon: EquippedWeaponFacts(
            item: FormID(0x12EB7), animationType: .oneHandSword, skill: 6
        ),
        hasShield: true,
        items: [
            EquippedItemFacts(keywords: [FormID(helmetKeyword)], isApparel: true, value: 60),
            EquippedItemFacts(keywords: [FormID(cuirassKeyword)], isApparel: true, value: 125),
            EquippedItemFacts(keywords: [], isApparel: false, value: 45)
        ]
    )

    private static func outcome(
        _ function: UInt16, equals value: Float, facts: ActorEquipmentFacts?,
        parameter1: UInt32 = 0, keywordCounts: [FormID: Int32] = [:]
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.inventory = InventoryConditionResolution(
            counts: [subject: [:]],
            equipment: facts.map { [subject: $0] } ?? [:],
            keywordCounts: [subject: keywordCounts]
        )
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: function, 0, value, parameter1: parameter1
        ))
    }

    @Test func equippedItemTypeReadsEachHand() throws {
        #expect(try Self.outcome(597, equals: 10, facts: Self.armed, parameter1: 0) == .true)
        #expect(try Self.outcome(597, equals: 1, facts: Self.armed, parameter1: 1) == .true)
        #expect(try Self.outcome(597, equals: 0, facts: Self.armed, parameter1: 2) == .true)
    }

    @Test func rightWeaponGivesAnimationTypeAndSkill() throws {
        #expect(try Self.outcome(108, equals: 1, facts: Self.armed) == .true)
        #expect(try Self.outcome(109, equals: 1, facts: Self.armed, parameter1: 6) == .true)
        #expect(try Self.outcome(109, equals: 0, facts: Self.armed, parameter1: 7) == .true)
        #expect(try Self.outcome(108, equals: 0, facts: ActorEquipmentFacts()) == .true)
    }

    @Test func wornKeywordsCountApparelOnly() throws {
        #expect(try Self
            .outcome(682, equals: 1, facts: Self.armed, parameter1: Self.helmetKeyword) == .true)
        #expect(try Self.outcome(
            722,
            equals: 1,
            facts: Self.armed,
            parameter1: Self.cuirassKeyword
        ) == .true)
        #expect(try Self.outcome(
            682,
            equals: 0,
            facts: ActorEquipmentFacts(),
            parameter1: Self.helmetKeyword
        ) == .true)
    }

    @Test func clothingValueSumsWornApparel() throws {
        #expect(try Self.outcome(41, equals: 185, facts: Self.armed) == .true)
    }

    @Test func keywordItemCountReadsTheInventory() throws {
        #expect(try Self.outcome(
            465, equals: 3, facts: nil, parameter1: Self.helmetKeyword,
            keywordCounts: [FormID(Self.helmetKeyword): 3]
        ) == .true)
    }

    @Test func noEquipmentFailsWithAReason() throws {
        #expect(try Self.outcome(597, equals: 0, facts: nil)
            .failures == [.unavailableData(.inventory)])
    }
}
