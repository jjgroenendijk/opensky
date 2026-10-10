// Constructor timing for a frame's placements. Synthetic fixtures only; no test
// reads a real `.swf` (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFRuntimeConstructionTests {
    typealias Action = AS2Fixture.Action

    /// A constructor reads a sibling the same frame places after it. Flash runs a
    /// frame's constructors once all its placements exist, and the race menu's
    /// panel constructor depends on that.
    @Test func aConstructorFindsASiblingPlacedLaterInTheSameFrame() throws {
        let body: [Action] = [
            AS2Fixture.push([.string("this")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("sibling"), .string("this")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("_parent")]), AS2Fixture.opcode(0x4E),
            AS2Fixture.push([.string("bar")]), AS2Fixture.opcode(0x4E),
            AS2Fixture.opcode(0x4F)
        ]
        let define = SWFActionFixture.defineFunction(
            name: "PanelClass", parameters: [], bodySize: UInt16(AS2Fixture.size(body))
        )
        let register = SWFRuntimeFixture.call(
            method: "registerClass", on: "Object",
            arguments: [
                [AS2Fixture.push([.string("PanelClip")])],
                [AS2Fixture.push([.string("PanelClass")]), AS2Fixture.opcode(0x1C)]
            ]
        )
        let sprite: (UInt16) -> SWFFixture.Tag = { id in
            SWFDisplayFixture.spriteTag(characterId: id, frameCount: 1, tags: [
                SWFRuntimeFixture.place(1, depth: 1), SWFDisplayFixture.showFrameTag
            ])
        }
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFRuntimeFixture.rectangle(id: 1), sprite(2), sprite(3),
            SWFDisplayFixture.exportAssetsTag([(2, "PanelClip")]),
            SWFActionFixture.doInitActionTag(spriteId: 2, [define] + body + register),
            SWFRuntimeFixture.place(2, depth: 1, name: "panel"),
            SWFRuntimeFixture.place(3, depth: 2, name: "bar"),
            SWFDisplayFixture.showFrameTag
        ])
        let panel = try #require(runtime.root.child(atDepth: 1))
        let bar = try #require(runtime.root.child(atDepth: 2))
        let sibling = panel.object.lookup("sibling")?.property.value.objectValue
        #expect(sibling === bar.object)
    }
}
