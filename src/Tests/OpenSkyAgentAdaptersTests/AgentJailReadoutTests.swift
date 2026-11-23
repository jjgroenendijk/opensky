// The alarm readout shows the player's jail stay and the followers waiting at the jail door.

import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import Testing

extension AgentReadoutTests {
    @Test func theAlarmStateShowsTheJailStayAndItsWaitingFollowers() throws {
        let follower = ReferenceKey.generated(7)
        host.crimeAlarmReadout = CrimeAlarmReadout(
            jail: JailStay(
                faction: .generated(1), nonViolentGold: 25, violentGold: 0, sentenceDays: 1,
                exteriorMarker: .generated(2), belongings: nil, outfit: [], arrestedIn: nil
            ),
            jailFollowers: [follower]
        )
        let state = try object(world.query(.alarm))
        let jail = object(state["jail"] ?? .null)
        #expect(jail["sentenceDays"] == AgentJSON(1))
        #expect(jail["inCell"] == .bool(false))
        #expect(state["jailFollowers"]?.arrayValue?.count == 1)
    }
}
