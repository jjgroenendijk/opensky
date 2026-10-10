// Synthetic PACK, NPC_ and ACHR records for the package tests. Built in code,
// never extracted from game data.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyWorld
@testable import OpenSkyWorldState

enum PackageRuntimeFixture {
    static func package(
        id: UInt32,
        editorID: String? = nil,
        schedule: Package.Schedule = .anytime,
        condition: ESMField? = nil,
        template: UInt32? = nil,
        procedureNames: [String] = [],
        dataInputs: [Package.DataInput] = []
    ) throws -> Package {
        var conditions = ConditionList()
        if let condition {
            try conditions.decode(field: condition)
        }
        return Package(
            formID: FormID(id),
            editorID: editorID,
            general: Package.GeneralData(
                flags: [],
                kind: .package,
                interruptOverride: 0,
                preferredSpeed: .walk,
                interruptFlags: 0
            ),
            schedule: schedule,
            conditions: conditions,
            template: template.map(FormID.init(stored:)),
            dataInputs: dataInputs,
            procedureTypes: procedureNames,
            scriptData: ScriptData(ownerType: "PACK"),
            skipped: FieldTally()
        )
    }

    static func actorBase(
        id: UInt32,
        templateFlags: UInt16 = 0,
        template: UInt32? = nil,
        packages: [UInt32]
    ) throws -> ActorBase {
        var acbs = Data(count: 18)
        acbs.appendUInt16(templateFlags)
        acbs.appendUInt32(0)
        var fields = ESMFixture.field("ACBS", acbs)
        if let template {
            fields += formIDField("TPLT", template)
        }
        for package in packages {
            fields += formIDField("PKID", package)
        }
        return try ActorBase(
            record: PackageFixture.parse(ESMFixture.record("NPC_", formID: id, data: fields)),
            localized: false
        )
    }

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    /// A resident ACHR placing `base`.
    static func residentActor(_ objectID: UInt32, base: UInt32) throws -> RuntimeReferenceEntry {
        let fields = ESMFixture.field("NAME", formIDData(base))
            + ESMFixture.field("DATA", Data(count: 24))
        let actor = try PlacedActor(record: ESMFixture.parseRecord(
            ESMFixture.record("ACHR", formID: objectID, data: fields)
        ))
        return RuntimeReferenceEntry(
            key: key(objectID), formID: FormID(objectID), isPersistent: true, record: .actor(actor)
        )
    }

    static func formIDField(_ type: String, _ value: UInt32) -> Data {
        ESMFixture.field(type, formIDData(value))
    }

    static func formIDData(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
