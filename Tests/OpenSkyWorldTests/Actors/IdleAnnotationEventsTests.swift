// An idle sends its clip's annotations as animation events, once per loop, between the
// notify events of its behavior state.

import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyWorld
import Testing

struct IdleAnnotationEventsTests {
    @Test func eachLoopSendsTheAnnotationsAgain() {
        let annotations = [
            HKAAnnotation(time: 0.5, text: "SoundPlay"),
            HKAAnnotation(time: 1.5, text: "CartExit")
        ]
        let events = IdleCore.annotationEvents(annotations, clipDuration: 2, seconds: 4)
        #expect(events.map(\.name) == ["SoundPlay", "CartExit", "SoundPlay", "CartExit"])
        #expect(events.map(\.time) == [0.5, 1.5, 2.5, 3.5])
    }

    @Test func anEventPastTheEndIsDropped() {
        let annotations = [HKAAnnotation(time: 1.5, text: "CartExit")]
        #expect(IdleCore.annotationEvents(annotations, clipDuration: 2, seconds: 1).isEmpty)
        #expect(IdleCore.annotationEvents(annotations, clipDuration: 0, seconds: 5).isEmpty)
    }

    /// The cart exit state sends `ExitCartBegin` as it starts and `ExitCartEnd` as it ends.
    @Test func theStateEventsFrameTheAnnotations() {
        let events = IdleCore.playEvents(
            annotations: [HKAAnnotation(time: 5.4, text: "CartExit")],
            notify: BehaviorStateNotify(enter: ["ExitCartBegin"], exit: ["ExitCartEnd"]),
            clipDuration: 5.6, seconds: 5.6
        )
        #expect(events.map(\.name) == ["ExitCartBegin", "CartExit", "ExitCartEnd"])
        #expect(events.map(\.time) == [0, 5.4, 5.6])
    }
}
