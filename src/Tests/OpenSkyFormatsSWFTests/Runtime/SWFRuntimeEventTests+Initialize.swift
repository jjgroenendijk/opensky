// The order of a placed clip's class, its `construct` handler, and its constructor.
// Synthetic fixtures only.

@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import Testing

extension SWFRuntimeEventTests {
    /// `_root.log = _root.log + typeof this.<member>`
    private static func logType(of member: String) -> [Action] {
        [
            AS2Fixture.push([.string("_root")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("log")]),
            AS2Fixture.push([.string("_root")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("log")]), AS2Fixture.opcode(0x4E),
            AS2Fixture.push([.string("this")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string(member)]), AS2Fixture.opcode(0x4E),
            AS2Fixture.opcode(0x44), AS2Fixture.opcode(0x47),
            AS2Fixture.opcode(0x4F)
        ]
    }

    /// A component's parameters sit in its `construct` handler, so the handler runs
    /// once the instance has its class and before the constructor, which reads them.
    /// The fixture class's constructor sets `built`.
    @Test func theConstructHandlerRunsWithTheClassBeforeTheConstructor() throws {
        let runtime = try SWFRuntimeFixture.started(
            tags: Self.lifecycleTags([
                SWFActionFixture.ClipHandler(
                    events: .construct, keyCode: nil,
                    actions: SWFActionFixture.stream(
                        Self.logType(of: "__constructor__") + Self.logType(of: "built")
                    )
                ),
                SWFActionFixture.ClipHandler(
                    events: .load, keyCode: nil,
                    actions: SWFActionFixture.stream(Self.logType(of: "built"))
                )
            ])
        )
        #expect(log(runtime) == "Cfunctionundefinednumber")
    }
}
