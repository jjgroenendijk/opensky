// MOVT decode and the movement-type index (issue #188), over synthetic record
// bytes built in code — never extracted game data (AGENTS.md "Legal & IP
// boundary"). Layout: UESP "Skyrim Mod:Mod File Format/MOVT".

import Foundation
@testable import opensky
import Testing

struct MovementTypeRecordTests {
    /// The 11 SPED floats, in file order. The forward pair is deliberately
    /// distinct from every other slot so a mis-ordered decode cannot pass.
    private static let speeds: [Float] = [
        1, 2, 3, 4, 47.2, 222, 7, 8, 9, 10, 11
    ]

    @Test
    func decodesEditorIDNameAndTheForwardSpeedPair() throws {
        let record = try Self.parse(Self.record(
            editorID: "NPC_Sneaking_MT", name: "NPCSneaking", speeds: Self.speeds
        ))
        let decoded = try MovementType(record: record)

        #expect(decoded.editorID == "NPC_Sneaking_MT")
        #expect(decoded.name == "NPCSneaking")
        #expect(decoded.speeds?.values == Self.speeds)
        #expect(decoded.speeds?.forwardWalk == 47.2)
        #expect(decoded.speeds?.forwardRun == 222)
    }

    @Test
    func aTruncatedSpeedStructIsDroppedWholeRatherThanZeroPadded() throws {
        let record = try Self.parse(Self.record(
            editorID: "Short_MT", name: nil, speeds: Array(Self.speeds.prefix(6))
        ))
        let decoded = try MovementType(record: record)

        #expect(decoded.editorID == "Short_MT")
        #expect(decoded.speeds == nil)
    }

    @Test
    func aNonMovementRecordThrows() throws {
        let record = try GlobalFixture.parse(GlobalFixture.record(
            formID: 1, editorID: "x", type: .float, value: 1
        ))
        #expect(throws: ESMError.self) {
            try MovementType(record: record)
        }
    }

    @Test
    func theIndexResolvesByEditorIDIgnoringCaseAndLastPluginWins() throws {
        let first = try ESMFile(data: Self.plugin(Self.record(
            editorID: "NPC_Default_MT", name: "NPCDefault", speeds: Self.speeds
        )))
        var raised = Self.speeds
        raised[5] = 400
        let second = try ESMFile(data: Self.plugin(Self.record(
            editorID: "NPC_Default_MT", name: "NPCDefault", speeds: raised
        )))
        let store = MovementTypeStore(plugins: [
            (name: "Base.esm", file: first), (name: "Patch.esp", file: second)
        ])

        #expect(store.type(editorID: "npc_default_mt")?.name == "NPCDefault")
        #expect(store.forwardSpeeds(editorID: "NPC_Default_MT")?.run == 400)
        #expect(store.forwardSpeeds(editorID: "missing") == nil)
    }

    @Test
    func gaitSpeedsResolveFromTheMovementTypesAndReportTheirSource() throws {
        var sprint = Self.speeds
        sprint[5] = 500
        let file = try ESMFile(data: Self.plugin(
            Self.record(editorID: "NPC_Sneaking_MT", name: nil, speeds: Self.speeds)
                + Self.record(editorID: "NPC_Sprinting_MT", name: nil, speeds: sprint)
        ))
        let configuration = PlayerMovementConfiguration.resolve(
            store: GameSettingStore(plugins: []),
            movementTypes: MovementTypeStore(plugins: [(name: "Base.esm", file: file)])
        )

        #expect(configuration.sneakSpeed.value == 47.2)
        #expect(configuration.sneakSpeed.source == "NPC_Sneaking_MT SPED forward walk")
        #expect(configuration.sprintSpeed.value == 500)
        // No NPC_Swimming_MT in this fixture, so the fallback has to say so.
        #expect(configuration.swimSpeed.source.hasPrefix("OpenSky fallback"))
    }

    @Test
    func jumpTakeoffSpeedComesFromTheJumpHeightSettingOverGravity() {
        let configuration = PlayerMovementConfiguration.resolve(
            store: GameSettingStore(plugins: [])
        )
        // fJumpHeightMin defaults to the shipped 76 units; the takeoff speed is
        // what reaches that height under the controller's gravity.
        let expected = (2 * WalkController.gravity * 76).squareRoot()
        #expect(abs(configuration.jumpTakeoffSpeed.value - expected) < 1e-3)
        #expect(configuration.jumpTakeoffSpeed.source.contains("fJumpHeightMin"))
    }

    // MARK: - Fixture

    private static func record(editorID: String, name: String?, speeds: [Float]) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let name {
            fields += ESMFixture.field("MNAM", ESMFixture.zstring(name))
        }
        var sped = Data()
        for value in speeds {
            sped.appendUInt32(value.bitPattern)
        }
        fields += ESMFixture.field("SPED", sped)
        return ESMFixture.record("MOVT", formID: 0x0100, flags: 0, data: fields)
    }

    private static func plugin(_ records: Data) -> Data {
        ESMFixture.tes4() + ESMFixture.topGroup("MOVT", contents: records)
    }

    private static func parse(_ bytes: Data) throws -> ESMRecord {
        try GlobalFixture.parse(bytes)
    }
}
