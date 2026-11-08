// PapyrusAnimationCensus: the event and variable names scripts pass as string
// literals, over synthetic PEX models.

import Foundation
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import Testing

struct PapyrusAnimationCensusTests {
    @Test func collectsRegisteredEventsAndVariables() {
        let call = { (name: String, argument: PexValue) in
            PapyrusTestSupport.instruction(
                .callMethod, .identifier(name), .identifier("self"),
                .identifier("::temp0"), .integer(1), argument
            )
        }
        let function = PexFixture.runtimeFunction(instructions: [
            call("RegisterForAnimationEvent", .string("DragonBiteEffect")),
            call("registerforanimationevent", .string("")),
            call("GetAnimationVariableBool", .string("IsAttacking")),
            call("GetAnimationVariableFloat", .string("Speed")),
            call("GetAnimationVariableInt", .identifier("asName")),
            call("SetAnimationVariableBool", .string("bAllowRotation"))
        ])
        let script = PexFixture.runtimeObject(name: "DragonScript", states: [
            PapyrusTestSupport.state(functions: [("OnLoad", function)])
        ])
        let census = PapyrusAnimationCensus(files: [PexFixture.runtimeFile(objects: [script])])

        #expect(census.registeredEvents == ["dragonbiteeffect"])
        #expect(census.readVariables == ["isattacking", "speed"])
        #expect(census.writtenVariables == ["ballowrotation"])
    }
}
