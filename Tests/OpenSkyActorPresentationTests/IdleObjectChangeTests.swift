// What a clip annotation does to an idle's animation object. Editor IDs are invented.

import Foundation
@testable import OpenSkyActorPresentation
import Testing

struct IdleObjectChangeTests {
    private static let key = IdleAnimationObject(
        editorID: "TestKey",
        prop: .attached(editorID: "TestKey", modelPath: "AnimObjects\\TestKey.nif", bone: "Hand"),
        unloadEvent: "TestUnequip"
    )

    @Test func drawShowsTheNamedObject() {
        let change = IdleCore.objectChange(
            for: "AnimObjDraw.testkey", objects: [Self.key], shown: nil
        )
        #expect(change == .show(Self.key))
    }

    @Test func loadAndUnknownObjectsChangeNothing() {
        #expect(IdleCore.objectChange(
            for: "AnimObjLoad.TestKey", objects: [Self.key], shown: nil
        ) == nil)
        #expect(IdleCore.objectChange(
            for: "AnimObjDraw.TestOther", objects: [Self.key], shown: nil
        ) == nil)
    }

    @Test func theShownObjectsUnloadEventRemovesIt() {
        #expect(IdleCore.objectChange(
            for: "testunequip", objects: [Self.key], shown: Self.key
        ) == .remove)
        #expect(IdleCore.objectChange(
            for: "TestUnequip", objects: [Self.key], shown: nil
        ) == nil)
    }
}
