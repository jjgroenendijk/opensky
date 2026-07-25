// ECMAScript coercion rules as ActionScript 2 uses them (milestone 8.3.2).
// These are the single most common source of subtle interpreter bugs, so the
// edge cases are pinned individually: undefined against null, NaN, -0, the
// empty string against zero, numeric strings, and the SWF 6 string rules.
//
// Reference: ECMA-262 3rd edition, sections 9.2, 9.3, 9.5, 9.6, 9.8, 11.8.5,
// and 11.9.3.

import Foundation
@testable import opensky
import Testing

struct AS2CoercionTests {
    private let coercion = AS2Coercion.latest

    @Test func toBooleanFollowsECMARules() {
        #expect(coercion.toBoolean(.undefined) == false)
        #expect(coercion.toBoolean(.null) == false)
        #expect(coercion.toBoolean(.number(0)) == false)
        #expect(coercion.toBoolean(.number(-0.0)) == false)
        #expect(coercion.toBoolean(.number(.nan)) == false)
        #expect(coercion.toBoolean(.number(-1)) == true)
        #expect(coercion.toBoolean(.string("")) == false)
        #expect(coercion.toBoolean(.string("0")) == true)
        #expect(coercion.toBoolean(.object(AS2Object())) == true)
    }

    @Test func swf6UsesTheNumericStringBooleanRule() {
        let legacy = AS2Coercion(swfVersion: 6)
        #expect(legacy.toBoolean(.string("0")) == false)
        #expect(legacy.toBoolean(.string("1")) == true)
        #expect(legacy.toBoolean(.string("abc")) == false)
        #expect(legacy.toString(.undefined).isEmpty)
        #expect(coercion.toString(.undefined) == "undefined")
    }

    @Test func toNumberParsesTheStringGrammar() {
        #expect(coercion.stringToNumber("") == 0)
        #expect(coercion.stringToNumber("   ") == 0)
        #expect(coercion.stringToNumber("  12  ") == 12)
        #expect(coercion.stringToNumber("-3.5") == -3.5)
        #expect(coercion.stringToNumber("1e3") == 1000)
        #expect(coercion.stringToNumber(".5") == 0.5)
        #expect(coercion.stringToNumber("0x10") == 16)
        #expect(coercion.stringToNumber("Infinity") == .infinity)
        #expect(coercion.stringToNumber("-Infinity") == -.infinity)
        #expect(coercion.stringToNumber("12abc").isNaN)
        #expect(coercion.stringToNumber("abc").isNaN)
        #expect(coercion.stringToNumber("inf").isNaN)
        #expect(coercion.stringToNumber("nan").isNaN)
    }

    @Test func toNumberOfSimpleValues() {
        #expect(coercion.toNumber(.null) == 0)
        #expect(coercion.toNumber(.undefined).isNaN)
        #expect(coercion.toNumber(.boolean(true)) == 1)
        #expect(coercion.toNumber(.boolean(false)) == 0)
    }

    @Test func numberToStringMatchesECMAFormatting() {
        #expect(AS2Coercion.numberToString(0) == "0")
        #expect(AS2Coercion.numberToString(-0.0) == "0")
        #expect(AS2Coercion.numberToString(5) == "5")
        #expect(AS2Coercion.numberToString(-5) == "-5")
        #expect(AS2Coercion.numberToString(1.5) == "1.5")
        #expect(AS2Coercion.numberToString(1e20) == "100000000000000000000")
        #expect(AS2Coercion.numberToString(1e21) == "1e+21")
        #expect(AS2Coercion.numberToString(1e-7) == "1e-7")
        #expect(AS2Coercion.numberToString(.nan) == "NaN")
        #expect(AS2Coercion.numberToString(.infinity) == "Infinity")
        #expect(AS2Coercion.numberToString(-.infinity) == "-Infinity")
    }

    @Test func abstractEqualityFollowsTheSpecOrder() {
        #expect(coercion.equals(.null, .undefined))
        #expect(coercion.equals(.undefined, .null))
        #expect(coercion.equals(.null, .null))
        #expect(!coercion.equals(.null, .number(0)))
        #expect(!coercion.equals(.undefined, .number(0)))
        #expect(!coercion.equals(.null, .string("")))
        #expect(coercion.equals(.string(""), .number(0)))
        #expect(coercion.equals(.string("1"), .boolean(true)))
        #expect(coercion.equals(.number(-0.0), .number(0)))
        #expect(!coercion.equals(.number(.nan), .number(.nan)))
        #expect(coercion.equals(.string("10"), .number(10)))
        #expect(!coercion.equals(.string("10a"), .number(10)))
    }

    @Test func strictEqualityComparesTypeAndIdentity() {
        #expect(AS2Value.string("1") != AS2Value.number(1))
        #expect(AS2Value.number(1) == AS2Value.number(1))
        #expect(AS2Value.number(.nan) != AS2Value.number(.nan))
        #expect(AS2Value.number(-0.0) == AS2Value.number(0))
        #expect(AS2Value.null != AS2Value.undefined)
        let object = AS2Object()
        #expect(AS2Value.object(object) == AS2Value.object(object))
        #expect(AS2Value.object(object) != AS2Value.object(AS2Object()))
    }

    @Test func relationalComparisonUsesStringOrderOnlyForTwoStrings() {
        #expect(coercion.lessThan(.string("a"), .string("b")))
        #expect(coercion.lessThan(.string("10"), .string("9")))
        #expect(!coercion.lessThan(.number(10), .string("9")))
        #expect(coercion.lessThan(.number(9), .string("10")))
        #expect(!coercion.lessThan(.number(.nan), .number(1)))
        #expect(!coercion.lessThan(.number(1), .number(.nan)))
    }

    @Test func integerConversionsWrapAtThirtyTwoBits() {
        #expect(AS2Coercion.toInt32(0) == 0)
        #expect(AS2Coercion.toInt32(-1) == -1)
        #expect(AS2Coercion.toInt32(4_294_967_296) == 0)
        #expect(AS2Coercion.toInt32(4_294_967_297) == 1)
        #expect(AS2Coercion.toInt32(2_147_483_648) == Int32.min)
        #expect(AS2Coercion.toInt32(1.9) == 1)
        #expect(AS2Coercion.toInt32(-1.9) == -1)
        #expect(AS2Coercion.toInt32(.nan) == 0)
        #expect(AS2Coercion.toInt32(.infinity) == 0)
        #expect(AS2Coercion.toUInt32(-1) == UInt32.max)
        #expect(AS2Coercion.toUInt32(4_294_967_296) == 0)
    }

    @Test func typeNamesMatchActionScript() {
        #expect(AS2Value.undefined.typeName == "undefined")
        #expect(AS2Value.null.typeName == "null")
        #expect(AS2Value.boolean(true).typeName == "boolean")
        #expect(AS2Value.number(1).typeName == "number")
        #expect(AS2Value.string("x").typeName == "string")
        #expect(AS2Value.object(AS2Object()).typeName == "object")
        let runtime = AS2Runtime()
        let function = runtime.makeNative("noop") { _ in .undefined }
        #expect(AS2Value.object(function).typeName == "function")
        let hosted = AS2Object()
        hosted.typeOverride = "movieclip"
        #expect(AS2Value.object(hosted).typeName == "movieclip")
    }
}
