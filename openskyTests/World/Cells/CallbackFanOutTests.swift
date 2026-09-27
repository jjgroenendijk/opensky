// CallbackFanOut (issue #171): registration order, multiple handlers, and the
// empty case that every engine seam sits in until something subscribes.

import Foundation
@testable import opensky
import Testing

@MainActor
struct CallbackFanOutTests {
    @Test func zeroHandlersIsANoOp() {
        let fanOut = CallbackFanOut<Int>()
        #expect(fanOut.handlerCount == 0)
        fanOut(1)
    }

    @Test func everyHandlerReceivesTheValue() {
        let fanOut = CallbackFanOut<Int>()
        var first: [Int] = []
        var second: [Int] = []
        fanOut.add { first.append($0) }
        fanOut.add { second.append($0) }
        fanOut(7)
        fanOut(9)
        #expect(fanOut.handlerCount == 2)
        #expect(first == [7, 9])
        #expect(second == [7, 9])
    }

    @Test func handlersRunInRegistrationOrder() {
        let fanOut = CallbackFanOut<String>()
        var order: [String] = []
        fanOut.add { order.append("first:\($0)") }
        fanOut.add { order.append("second:\($0)") }
        fanOut.add { order.append("third:\($0)") }
        fanOut("x")
        #expect(order == ["first:x", "second:x", "third:x"])
    }

    /// The two-argument engine callbacks pass a tuple rather than growing a
    /// second generic parameter.
    @Test func tupleValueCarriesSeveralArguments() {
        let fanOut = CallbackFanOut<(Int, Bool)>()
        var received: [String] = []
        fanOut.add { received.append("\($0.0)/\($0.1)") }
        fanOut((3, true))
        #expect(received == ["3/true"])
    }

    /// A handler added while the fan-out is idle joins the next delivery, which
    /// is how setup code wires one seam from several places.
    @Test func aLateHandlerJoinsTheNextDelivery() {
        let fanOut = CallbackFanOut<Int>()
        var early: [Int] = []
        var late: [Int] = []
        fanOut.add { early.append($0) }
        fanOut(1)
        fanOut.add { late.append($0) }
        fanOut(2)
        #expect(early == [1, 2])
        #expect(late == [2])
    }
}
