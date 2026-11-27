import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import Testing

struct VanillaDataRulesTests {
    /// `GetIsID(base) <operator> value` on the subject; operator 0 is ==, 1 is !=.
    private func isID(_ base: UInt32, operatorBits: UInt8 = 0, value: Float = 1, flags: UInt8 = 0)
        throws -> Condition
    {
        let field = DialogueFixture.condition(
            functionIndex: 72, operatorBits: operatorBits, flags: flags,
            comparisonValue: value, parameter1: base
        )
        let payload = Data(field.dropFirst(6))
        let condition = try Condition(ctda: ESMField(type: "CTDA", data: payload))
        return try #require(condition)
    }

    @Test func twoAnswersToOneQuestionNeverPass() throws {
        #expect(try VanillaDataRules.contradicts([isID(7, value: 1), isID(7, value: 0)]))
        #expect(try VanillaDataRules.contradicts([isID(7), isID(7, operatorBits: 1)]))
    }

    @Test func differentQuestionsOrAnOrAreNotJudged() throws {
        #expect(try !VanillaDataRules.contradicts([isID(7), isID(8)]))
        #expect(try !VanillaDataRules.contradicts([isID(7, flags: 1), isID(7, value: 0)]))
        #expect(try !VanillaDataRules.contradicts([isID(7), isID(7)]))
    }
}
