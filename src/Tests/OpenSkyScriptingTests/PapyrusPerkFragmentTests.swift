// Perk fragments under the Papyrus world runtime: an Activate choice runs one
// fragment of the perk's fragment script, with the target first and the actor second.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusPerkFragmentTests {
    private static let perkObjectID: UInt32 = 0x2100
    private static let script = "PRKF_FeedPerk_00002100"

    private var perkKey: ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: Self.perkObjectID)
    }

    private func perk() throws -> Perk {
        let fields = PerkFixture.fields(editorID: "FeedPerk")
            + PerkFixture.fragmentVMAD(
                fileName: Self.script,
                fragments: [(index: 0, function: "Fragment_0"), (index: 1, function: "Fragment_15")]
            )
        return try Perk(
            record: PerkFixture.record(formID: Self.perkObjectID, fields: fields), localized: false
        )
    }

    private func fragmentScript() -> PexObject {
        let parameters = [
            PexTypedName(name: "akTargetRef", typeName: "ObjectReference"),
            PexTypedName(name: "akActor", typeName: "Actor")
        ]
        let body = PapyrusWorldFixture.probeBody(note: "perk.fragment15")
        return PapyrusWorldFixture.eventScript(Self.script, events: [(
            "Fragment_15",
            PexFixture.runtimeFunction(parameters: parameters, instructions: body.instructions)
        )])
    }

    @Test func aFragmentRunsOnThePerkWithTheTargetAndTheActor() throws {
        let session = PapyrusWorldFixture.session(objects: [fragmentScript()], entries: [])
        PapyrusWorldFixture.drain(session.world)
        let target = ReferenceKey.plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x9001)

        #expect(try session.bridge.runPerkFragment(
            of: perk(), key: perkKey, index: 1,
            activation: PerkFragmentActivation(actor: .player, target: target)
        ))
        let event = try #require(session.world.eventQueue.last)
        #expect(event.functionName == "Fragment_15")
        #expect(event.arguments == [
            .object(session.world.objectHandle(for: target)),
            .object(session.world.objectHandle(for: .player))
        ])

        PapyrusWorldFixture.drain(session.world)
        #expect(session.dispatch.notes == ["perk.fragment15"])
        let key = PapyrusInstanceKey(reference: perkKey, scriptName: Self.script)
        #expect(session.world.persistentKeys.contains(key))
    }

    @Test func anIndexTheTableDoesNotNameRunsNothing() throws {
        let session = PapyrusWorldFixture.session(objects: [fragmentScript()], entries: [])
        #expect(try !session.bridge.runPerkFragment(
            of: perk(), key: perkKey, index: 7,
            activation: PerkFragmentActivation(actor: .player, target: perkKey)
        ))
        #expect(session.world.eventQueue.isEmpty)
    }
}
