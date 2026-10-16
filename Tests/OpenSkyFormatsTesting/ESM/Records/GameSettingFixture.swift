// Single-GMST plugins for the game-setting store and the settings it feeds.

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

/// One synthetic GMST value, typed by its editor ID's first letter in the game.
public enum GameSettingFixtureValue: Sendable {
    case float(Float)
    case integer(Int32)
    case boolean(Bool)
    /// An inline string; the plugin is not localized.
    case text(String)

    var data: Data {
        var data = Data()
        switch self {
        case let .float(value): data.appendUInt32(value.bitPattern)
        case let .integer(value): data.appendUInt32(UInt32(bitPattern: value))
        case let .boolean(value): data.appendUInt32(value ? 1 : 0)
        case let .text(value): data = ESMFixture.zstring(value)
        }
        return data
    }
}

extension GameSettingFixture {
    /// A plugin with one GMST per entry, in editor ID order.
    public static func plugin(settings: [String: GameSettingFixtureValue]) throws -> ESMFile {
        let records = settings.sorted { $0.key < $1.key }.enumerated().reduce(into: Data()) {
            let fields = ESMFixture.field("EDID", ESMFixture.zstring($1.element.key))
                + ESMFixture.field("DATA", $1.element.value.data)
            $0 += ESMFixture.record("GMST", formID: UInt32($1.offset + 1), data: fields)
        }
        return try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup("GMST", contents: records))
    }
}
