// The readout of an actor no package drives.

@testable import OpenSkyAIPackages
import OpenSkyFormatsESM
import Testing

struct AINavigationCoreTests {
    @Test func anEmptyReadoutNamesOnlyTheActor() {
        let actor = ReferenceKey.plugin(name: "Skyrim.esm", objectID: 0x1234)
        let readout = AINavigationCore.emptyPackageReadout(actor)
        #expect(readout.actor == actor)
        #expect(readout.actorBase == FormID(0))
        #expect(readout.currentPackage == nil)
        #expect(readout.editorID == nil)
        #expect(readout.schedule == nil)
        #expect(readout.procedure == nil)
        #expect(readout.lastEvaluationGameSeconds == nil)
        #expect(!readout.isSuspended)
    }
}
