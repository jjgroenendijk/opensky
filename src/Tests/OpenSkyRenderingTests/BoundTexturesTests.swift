// The texture slots a run of group draws holds: a slot is set again only when its
// texture changes, and a new run sets every slot.

import Metal
@testable import OpenSkyRendering
import Testing

struct BoundTexturesTests {
    /// Whether each `(id, slot)` call changed its slot, in order, on one run.
    private static func changes(_ calls: [(UInt64, Int)], on bound: inout Renderer.BoundTextures)
        -> [Bool]
    {
        calls.map { bound.changes(MTLResourceID(_impl: $0.0), at: $0.1) }
    }

    @Test func aSlotChangesOnlyWhenItsTextureDoes() {
        var bound = Renderer.BoundTextures()
        let changed = Self.changes([(7, 1), (7, 1), (7, 2), (8, 1), (8, 1)], on: &bound)
        #expect(changed == [true, false, true, true, false])
    }

    @Test func aNewRunAndAnUnknownSlotAlwaysSet() {
        var bound = Renderer.BoundTextures()
        _ = Self.changes([(7, 1)], on: &bound)
        bound = Renderer.BoundTextures()
        let changed = Self.changes([(7, 1), (7, 40), (7, 40)], on: &bound)
        #expect(changed == [true, true, true])
    }
}
