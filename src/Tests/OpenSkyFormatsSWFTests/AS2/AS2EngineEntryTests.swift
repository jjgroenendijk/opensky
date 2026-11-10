// The engine's entry points into a runtime: calling a built-in and
// constructing an instance from Swift. See docs/engine/as2-runtime.md.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct AS2EngineEntryTests {
    @Test func theBooleanBuiltInCoercesItsArgument() {
        let runtime = AS2Runtime()
        let boolean = runtime.globalValue("Boolean")
        #expect(AS2Interpreter.invoke(in: runtime, boolean, arguments: [.number(2)]).value
            == .boolean(true))
        #expect(AS2Interpreter.invoke(in: runtime, boolean, arguments: [.string("")]).value
            == .boolean(false))
    }

    @Test func constructRunsTheConstructorOnAnInstanceOfItsPrototype() throws {
        let runtime = AS2Runtime()
        let prototype = runtime.makeObject()
        let constructor = runtime.makeNative { context in
            context.thisObject?.define(context.argument(0), for: "code")
            return .undefined
        }
        constructor.define(.object(prototype), for: "prototype")
        let made = AS2Interpreter.construct(in: runtime, constructor, arguments: [.integer(7)])
        let instance = try #require(made.objectValue)
        #expect(instance.prototype === prototype)
        #expect(instance.lookup("code")?.property.value == .integer(7))
    }

    @Test func constructOfAnObjectWithoutAPrototypeIsUndefined() {
        let runtime = AS2Runtime()
        #expect(AS2Interpreter.construct(in: runtime, runtime.makeObject()) == .undefined)
    }
}
