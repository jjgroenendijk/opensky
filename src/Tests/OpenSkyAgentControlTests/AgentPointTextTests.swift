// A point typed as x,y,z, with or without spaces.

@testable import OpenSkyAgentControl
import Testing

struct AgentPointTextTests {
    @Test
    func readsThreeNumbers() {
        #expect(AgentArguments.point(fromText: "1,2,3") == SIMD3(1, 2, 3))
        #expect(AgentArguments.point(fromText: " -4.5, 0 ,7") == SIMD3(-4.5, 0, 7))
    }

    @Test
    func rejectsAnythingElse() {
        #expect(AgentArguments.point(fromText: "1,2") == nil)
        #expect(AgentArguments.point(fromText: "1,2,x") == nil)
        #expect(AgentArguments.point(fromText: "player") == nil)
        #expect(AgentArguments.point(fromText: "1,2,inf") == nil)
    }
}
