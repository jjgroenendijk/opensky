// The alias reads hand back the reference the alias property is bound to.

import Foundation
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeReferenceAliasTests {
    @Test func aliasReadsReturnTheBoundReference() {
        var registry = PapyrusNativeRegistry()
        PapyrusNativeFunctions.installReferenceAlias(into: &registry)
        let marker = PapyrusObjectHandle(42)
        for name in PapyrusNativeFunctions.referenceAliasReads {
            let call = PapyrusWorldFixture.methodCall(
                "ReferenceAlias", name, receiver: marker, returnType: .object("ObjectReference")
            )
            #expect(registry.invoke(call) == .returned(.object(marker)))
        }
    }
}
