import Foundation
@testable import opensky
import Testing

struct PapyrusCoercionTests {
    private let coercion = PapyrusCoercion()

    @Test func truthinessCoversEveryValueKind() {
        let array = PapyrusArray(elementType: .integer, elements: [.integer(0)])
        #expect(!coercion.toBoolean(.none))
        #expect(!coercion.toBoolean(.boolean(false)))
        #expect(!coercion.toBoolean(.integer(0)))
        #expect(!coercion.toBoolean(.float(0)))
        #expect(!coercion.toBoolean(.string("")))
        #expect(coercion.toBoolean(.boolean(true)))
        #expect(coercion.toBoolean(.integer(-1)))
        #expect(coercion.toBoolean(.float(0.5)))
        #expect(coercion.toBoolean(.string("x")))
        #expect(coercion.toBoolean(.object(PapyrusObjectHandle(1))))
        #expect(coercion.toBoolean(.array(array)))
        #expect(!coercion.toBoolean(.array(PapyrusArray(elementType: .integer, elements: []))))
    }

    @Test func numericCastsCoverBooleansStringsAndHex() throws {
        #expect(try coercion.toInteger(.boolean(true)) == 1)
        #expect(try coercion.toInteger(.float(3.9)) == 3)
        #expect(try coercion.toInteger(.string("-12")) == -12)
        #expect(try coercion.toInteger(.string("0xFFFFFFFF")) == -1)
        #expect(try coercion.toFloat(.integer(7)) == 7)
        #expect(try coercion.toFloat(.string("2.5")) == 2.5)
    }

    @Test func stringCastsCoverEveryValueKind() {
        #expect(coercion.toString(.none) == "None")
        #expect(coercion.toString(.boolean(true)) == "True")
        #expect(coercion.toString(.integer(-3)) == "-3")
        #expect(coercion.toString(.float(1.5)) == "1.5")
        #expect(coercion.toString(.string("text")) == "text")
        #expect(coercion.toString(.object(PapyrusObjectHandle(9))) == "[Object 9]")
        let array = PapyrusArray(elementType: .string, elements: [])
        #expect(coercion.toString(.array(array)) == "[String array 0]")
    }

    @Test func invalidNumericCastsAreTypedErrors() {
        #expect(throws: PapyrusCoercionError.self) {
            try coercion.toInteger(.string("not a number"))
        }
        #expect(throws: PapyrusCoercionError.self) {
            try coercion.toFloat(.object(PapyrusObjectHandle(1)))
        }
    }
}
