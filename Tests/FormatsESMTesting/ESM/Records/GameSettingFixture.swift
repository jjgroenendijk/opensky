// Single-GMST plugins for the game-setting store and the settings it feeds.

import FormatsCoreTesting
import Foundation
@testable import OpenSkyFormatsESM

public enum GameSettingFixture: Sendable {
    /// A plugin with one float GMST.
    public static func plugin(editorID: String, value: Float, formID: UInt32) throws -> ESMFile {
        var data = Data()
        data.appendUInt32(value.bitPattern)
        return try plugin(editorID: editorID, rawData: data, formID: formID)
    }

    /// A plugin with one GMST whose DATA is `rawData`, valid or not.
    public static func plugin(editorID: String, rawData: Data, formID: UInt32) throws -> ESMFile {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("DATA", rawData)
        return try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "GMST",
            contents: ESMFixture.record("GMST", formID: formID, data: fields)
        ))
    }
}
