// Player movement tuning resolved from GMST game settings. In-code plugin fixtures only.

@testable import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyEngine
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct PlayerMovementConfigurationTests {
    @Test
    func movementResolutionUsesValidFloatsAndExplicitFallbacks() throws {
        let file = try plugin(editorID: "fMoveCharWalkBase", value: 125, formID: 1)
        let configuration = PlayerMovementConfiguration.resolve(
            store: GameSettingStore(plugins: [("Tuning.esp", file)])
        )
        #expect(configuration.walkSpeed == MovementSetting(value: 125, source: "Tuning.esp"))
        #expect(configuration.runSpeed == MovementSetting(value: 370, source: "engine default"))
        #expect(configuration.stepHeight.value == 32)
        #expect(configuration.stepHeight.source.contains("no confirmed"))
    }

    private func plugin(editorID: String, value: Float, formID: UInt32) throws -> ESMFile {
        try plugin(editorID: editorID, rawData: scalar(value.bitPattern), formID: formID)
    }

    private func plugin(editorID: String, rawData: Data, formID: UInt32) throws -> ESMFile {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("DATA", rawData)
        return try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "GMST",
            contents: ESMFixture.record("GMST", formID: formID, data: fields)
        ))
    }

    private func scalar(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
