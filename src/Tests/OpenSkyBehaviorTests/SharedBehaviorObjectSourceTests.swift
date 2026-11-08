// The shared source answers as the packfile source does, and keeps its answer for every
// instance built over the same file.

@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import Testing

struct SharedBehaviorObjectSourceTests {
    @Test func itAnswersAsThePackfileSourceDoes() throws {
        var fixture = HKBNodeFixture(payloadSize: 0x200)
        let clip = fixture.addObject("hkbClipGenerator", at: 0)
        let graph = try fixture.buildGraph()
        let shared = SharedBehaviorObjectSource(graph: graph)
        let plain = HKXBehaviorObjectSource(graph: graph)
        let empty = HKXPointerTarget(sectionIndex: HKBNodeFixture.dataSection, dataOffset: 0x180)

        for _ in 0 ..< 2 {
            #expect(shared.object(at: clip)?.className == plain.object(at: clip)?.className)
            #expect(shared.object(at: clip)?.className == "hkbClipGenerator")
            #expect(shared.object(at: empty) == nil)
            #expect(shared.className(at: clip) == plain.className(at: clip))
        }
    }

    @Test func twoInstancesOverOneFileShareItsObjects() throws {
        var fixture = HKBNodeFixture(payloadSize: 0x200)
        let clip = fixture.addObject("hkbClipGenerator", at: 0)
        let graph = try fixture.buildGraph()
        let shared = SharedBehaviorObjectSource(graph: graph)
        let skeleton = BehaviorSkeleton(referencePose: [], parentIndices: [])
        let first = BehaviorGraphInstance(root: clip, data: nil, source: shared, skeleton: skeleton)
        let second = BehaviorGraphInstance(
            root: clip,
            data: nil,
            source: shared,
            skeleton: skeleton
        )

        #expect(first.object(at: clip)?.className == "hkbClipGenerator")
        #expect(second.object(at: clip)?.className == "hkbClipGenerator")
    }
}
