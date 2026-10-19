// Clip annotation text to animation object event. The editor IDs are invented.

import Foundation
@testable import OpenSkyBehavior
import Testing

struct AnimationObjectEventTests {
    @Test func loadAndDrawNameTheirObject() {
        #expect(AnimationObjectEvent.parse("AnimObjLoad.TestKey") == .load(editorID: "TestKey"))
        #expect(AnimationObjectEvent.parse("animObjDraw.TestKey") == .draw(editorID: "TestKey"))
    }

    @Test func otherAnnotationsAreNotObjectEvents() {
        #expect(AnimationObjectEvent.parse("AnimObjDraw.") == nil)
        #expect(AnimationObjectEvent.parse("AnimObjectUnequip") == nil)
        #expect(AnimationObjectEvent.parse("SoundPlay.TestKey") == nil)
    }

    @Test func editorIDsAreListedOnceInOrder() {
        let texts = [
            "AnimObjLoad.TestHead",
            "HitFrame",
            "AnimObjLoad.TestNeck",
            "AnimObjDraw.testhead"
        ]
        #expect(AnimationObjectEvent.editorIDs(in: texts) == ["TestHead", "TestNeck"])
    }
}
