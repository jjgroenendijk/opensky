// The dialogue menu readout lists the topics that offered the speaker nothing, so a missing
// choice can be explained from the running game.

import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyMenusInterface
import OpenSkySessionInterface
import OpenSkySessionTesting
import Testing

extension AgentReadoutTests {
    @Test func anOpenDialogueMenuListsTheTopicsThatOfferedNothing() throws {
        host.fakeMenuMode.topMenu = .dialogueMenu
        host.fakeDialogueMenu.snapshotValue = DialogueControlSnapshot(
            isOpen: true, openMenus: ["Dialogue Menu"], worldSimPaused: false, rows: [],
            selectedIndex: -1, subtitle: "Stop right there!",
            rejections: [DialogueRejectionRow(
                topic: FormID(0x267DD),
                reasons: ["conditions failed"]
            )],
            unresolvedConditionCount: 2
        )
        let state = try object(world.query(.menu))
        let dialogue = object(state["dialogue"] ?? .null)
        #expect(dialogue["subtitle"] == .string("Stop right there!"))
        #expect(dialogue["unresolvedConditions"] == .init(2))
        guard case let .array(rejected)? = dialogue["rejected"], let first = rejected.first else {
            Issue.record("no rejected list")
            return
        }
        #expect(object(first)["reasons"] == .array([.string("conditions failed")]))
    }
}
