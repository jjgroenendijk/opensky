// PapyrusEventCensus: events engine classes declare, the scripts that handle them, and
// which ones the engine sends, over synthetic PEX models.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import Testing

struct PapyrusEventCensusTests {
    private let empty = PexFixture.runtimeFunction(instructions: [])

    @Test func countsScriptsPerHandledEvent() {
        let native = PexFixture.runtimeFunction(flags: .native, instructions: [])
        let engineClass = PexFixture.runtimeObject(name: "ObjectReference", states: [
            PapyrusTestSupport.state(functions: [
                ("GetPositionX", native), ("OnHit", empty), ("OnUnsentEvent", empty)
            ])
        ])
        let door = script("DoorScript", handles: ["OnHit", "OnUnsentEvent", "OnCustom"])
        let chest = script("ChestScript", handles: ["onhit"])
        let census = PapyrusEventCensus(
            files: [PexFixture.runtimeFile(objects: [engineClass, door, chest])]
        )

        #expect(census.declaredEventCount == 2)
        #expect(census.handlers.uses == ["OnHit": 2, "OnUnsentEvent": 1])
        #expect(census.handlers.left(where: PapyrusEventCensus.isSent)
            .map(\.name) == ["OnUnsentEvent"])
    }

    @Test func everySentEventIsListed() {
        #expect(PapyrusEventCensus.isSent(PapyrusEngineEvents.onTriggerEnter))
        #expect(PapyrusEngineEvents.sent.count == 58)
    }

    private func script(_ name: String, handles events: [String]) -> PexObject {
        PexFixture.runtimeObject(
            name: name,
            parent: "ObjectReference",
            states: [PapyrusTestSupport.state(functions: events.map { ($0, empty) })]
        )
    }
}
