// LCTN locations and LCRT location-reference types. LCTN ties named places
// to parent locations, keywords, persistent references, unique actors and
// typed special references. Its packed arrays are sized from payload bytes;
// a partial trailing element is dropped and measured rather than read past.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/LCTN" and "/LCRT":
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LCTN
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LCRT
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(LCTN, ...)`
//   and `wbRecord(LCRT, ...)`.
// Layout documented in docs/formats/locations.md.

import Foundation

nonisolated public struct LocationRefType: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let editorColor: ReferenceRecordColor?
    public let skipped: ReferenceRecordTally

    public init(record: ESMRecord) throws {
        guard record.type == "LCRT" else {
            throw ESMError.malformed("expected LCRT record, got \(record.type)")
        }
        let decoded = try ReferenceRecordFields(record: record)
        formID = FormID(record.formID)
        editorID = decoded.editorID
        editorColor = decoded.editorColor
        skipped = decoded.skipped
    }
}

nonisolated public struct LocationDecodeTally: Equatable, Sendable {
    public private(set) var malformedFields: [FourCC: Int] = [:]
    /// Number of bytes dropped after the last whole packed-array element.
    public private(set) var trailingArrayBytes: [FourCC: Int] = [:]
    public private(set) var unknownFields: [FourCC: Int] = [:]

    public mutating func noteMalformed(_ type: FourCC) {
        malformedFields[type, default: 0] += 1
    }

    public mutating func noteTail(_ type: FourCC, bytes: Int) {
        guard bytes > 0 else { return }
        trailingArrayBytes[type, default: 0] += bytes
    }

    public mutating func noteUnknown(_ type: FourCC) {
        unknownFields[type, default: 0] += 1
    }
}

nonisolated public struct Location: Equatable, Sendable {
    public struct PersistentReference: Equatable, Sendable {
        public let reference: FormID
        public let worldOrCell: FormID
        public let gridY: Int16
        public let gridX: Int16
    }

    public struct UniqueActor: Equatable, Sendable {
        public let actorBase: FormID
        public let actorReference: FormID
        public let location: FormID
    }

    public struct SpecialReference: Equatable, Sendable {
        public let type: FormID
        public let reference: FormID
        public let worldOrCell: FormID
        public let gridY: Int16
        public let gridX: Int16
    }

    public struct WorldspaceCells: Equatable, Sendable {
        public struct Grid: Equatable, Sendable {
            public let y: Int16
            public let x: Int16
        }

        public let worldspace: FormID
        public let cells: [Grid]
    }

    public struct EnableParent: Equatable, Sendable {
        public let reference: FormID
        public let parent: FormID
        public let flags: UInt8
    }

    public let formID: FormID
    public let editorID: String?
    public let name: LString?
    public let parent: FormID?
    public let keywords: KeywordList

    public let addedPersistentReferences: [PersistentReference]
    public let persistentReferences: [PersistentReference]
    public let removedPersistentReferences: [FormID]
    public let addedUniqueActors: [UniqueActor]
    public let uniqueActors: [UniqueActor]
    public let removedUniqueActors: [FormID]
    public let addedSpecialReferences: [SpecialReference]
    public let specialReferences: [SpecialReference]
    public let removedSpecialReferences: [FormID]
    public let addedWorldspaceCells: [WorldspaceCells]
    public let worldspaceCells: [WorldspaceCells]
    public let removedWorldspaceCells: [WorldspaceCells]
    public let addedInitiallyDisabledReferences: [FormID]
    public let initiallyDisabledReferences: [FormID]
    public let addedEnableParents: [EnableParent]
    public let enableParents: [EnableParent]

    public let music: FormID?
    public let crimeFaction: FormID?
    public let worldMarker: FormID?
    public let worldRadius: Float?
    public let horseMarker: FormID?
    public let editorColor: ReferenceRecordColor?
    public let skipped: LocationDecodeTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "LCTN" else {
            throw ESMError.malformed("expected LCTN record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var fields = Fields()
        for field in try record.fields() {
            fields.decode(field, localized: localized)
        }
        editorID = fields.editorID
        name = fields.name
        parent = fields.parent
        keywords = fields.keywords
        addedPersistentReferences = fields.addedPersistentReferences
        persistentReferences = fields.persistentReferences
        removedPersistentReferences = fields.removedPersistentReferences
        addedUniqueActors = fields.addedUniqueActors
        uniqueActors = fields.uniqueActors
        removedUniqueActors = fields.removedUniqueActors
        addedSpecialReferences = fields.addedSpecialReferences
        specialReferences = fields.specialReferences
        removedSpecialReferences = fields.removedSpecialReferences
        addedWorldspaceCells = fields.addedWorldspaceCells
        worldspaceCells = fields.worldspaceCells
        removedWorldspaceCells = fields.removedWorldspaceCells
        addedInitiallyDisabledReferences = fields.addedInitiallyDisabledReferences
        initiallyDisabledReferences = fields.initiallyDisabledReferences
        addedEnableParents = fields.addedEnableParents
        enableParents = fields.enableParents
        music = fields.music
        crimeFaction = fields.crimeFaction
        worldMarker = fields.worldMarker
        worldRadius = fields.worldRadius
        horseMarker = fields.horseMarker
        editorColor = fields.editorColor
        skipped = fields.skipped
    }
}

nonisolated extension Location {
    fileprivate struct Fields {
        var editorID: String?
        var name: LString?
        var parent: FormID?
        var keywords = KeywordList()
        var addedPersistentReferences: [PersistentReference] = []
        var persistentReferences: [PersistentReference] = []
        var removedPersistentReferences: [FormID] = []
        var addedUniqueActors: [UniqueActor] = []
        var uniqueActors: [UniqueActor] = []
        var removedUniqueActors: [FormID] = []
        var addedSpecialReferences: [SpecialReference] = []
        var specialReferences: [SpecialReference] = []
        var removedSpecialReferences: [FormID] = []
        var addedWorldspaceCells: [WorldspaceCells] = []
        var worldspaceCells: [WorldspaceCells] = []
        var removedWorldspaceCells: [WorldspaceCells] = []
        var addedInitiallyDisabledReferences: [FormID] = []
        var initiallyDisabledReferences: [FormID] = []
        var addedEnableParents: [EnableParent] = []
        var enableParents: [EnableParent] = []
        var music: FormID?
        var crimeFaction: FormID?
        var worldMarker: FormID?
        var worldRadius: Float?
        var horseMarker: FormID?
        var editorColor: ReferenceRecordColor?
        var skipped = LocationDecodeTally()

        mutating func decode(_ field: ESMField, localized: Bool) {
            do {
                if try keywords.decode(field: field) {
                    return
                }
                try decodeKnown(field, localized: localized)
            } catch {
                skipped.noteMalformed(field.type)
            }
        }

        private mutating func decodeKnown(_ field: ESMField, localized: Bool) throws {
            switch field.type {
            case "EDID":
                var reader = BinaryReader(field.data)
                editorID = try reader.readZString()
            case "FULL": name = try LString(field: field, localized: localized)
            case "PNAM": parent = try scalarFormID(field)
            case "NAM1": music = try scalarFormID(field)
            case "FNAM": crimeFaction = try scalarFormID(field)
            case "MNAM": worldMarker = try scalarFormID(field)
            case "RNAM": worldRadius = try scalarFloat(field)
            case "NAM0": horseMarker = try scalarFormID(field)
            case "CNAM": editorColor = try color(field)
            default: try decodeArray(field)
            }
        }

        private mutating func decodeArray(_ field: ESMField) throws {
            switch field.type {
            case "ACPR": addedPersistentReferences += try persistent(field)
            case "LCPR": persistentReferences += try persistent(field)
            case "RCPR": removedPersistentReferences += try formIDs(field)
            case "ACUN": addedUniqueActors += try actors(field)
            case "LCUN": uniqueActors += try actors(field)
            case "RCUN": removedUniqueActors += try formIDs(field)
            case "ACSR": addedSpecialReferences += try special(field)
            case "LCSR": specialReferences += try special(field)
            case "RCSR": removedSpecialReferences += try formIDs(field)
            default: try decodeSecondaryArray(field)
            }
        }

        private mutating func decodeSecondaryArray(_ field: ESMField) throws {
            switch field.type {
            case "ACEC": try addedWorldspaceCells.append(cells(field))
            case "LCEC": try worldspaceCells.append(cells(field))
            case "RCEC": try removedWorldspaceCells.append(cells(field))
            case "ACID": addedInitiallyDisabledReferences += try formIDs(field)
            case "LCID": initiallyDisabledReferences += try formIDs(field)
            case "ACEP": addedEnableParents += try parents(field)
            case "LCEP": enableParents += try parents(field)
            default: skipped.noteUnknown(field.type)
            }
        }

        private mutating func scalarFormID(_ field: ESMField) throws -> FormID? {
            guard field.data.count >= 4 else {
                skipped.noteMalformed(field.type)
                return nil
            }
            var reader = BinaryReader(field.data)
            let value = try FormID(reader.readUInt32())
            return value.isNull ? nil : value
        }

        private mutating func scalarFloat(_ field: ESMField) throws -> Float? {
            guard field.data.count >= 4 else {
                skipped.noteMalformed(field.type)
                return nil
            }
            var reader = BinaryReader(field.data)
            return try Float(bitPattern: reader.readUInt32())
        }

        private mutating func color(_ field: ESMField) throws -> ReferenceRecordColor? {
            guard field.data.count >= 4 else {
                skipped.noteMalformed(field.type)
                return nil
            }
            var reader = BinaryReader(field.data)
            return try ReferenceRecordColor(reader: &reader)
        }

        private mutating func persistent(_ field: ESMField) throws -> [PersistentReference] {
            skipped.noteTail(field.type, bytes: field.data.count % 12)
            var reader = BinaryReader(field.data)
            var values: [PersistentReference] = []
            values.reserveCapacity(field.data.count / 12)
            for _ in 0 ..< (field.data.count / 12) {
                try values.append(PersistentReference(
                    reference: FormID(reader.readUInt32()),
                    worldOrCell: FormID(reader.readUInt32()),
                    gridY: Int16(bitPattern: reader.readUInt16()),
                    gridX: Int16(bitPattern: reader.readUInt16())
                ))
            }
            return values
        }

        private mutating func actors(_ field: ESMField) throws -> [UniqueActor] {
            skipped.noteTail(field.type, bytes: field.data.count % 12)
            var reader = BinaryReader(field.data)
            var values: [UniqueActor] = []
            values.reserveCapacity(field.data.count / 12)
            for _ in 0 ..< (field.data.count / 12) {
                try values.append(UniqueActor(
                    actorBase: FormID(reader.readUInt32()),
                    actorReference: FormID(reader.readUInt32()),
                    location: FormID(reader.readUInt32())
                ))
            }
            return values
        }

        private mutating func special(_ field: ESMField) throws -> [SpecialReference] {
            skipped.noteTail(field.type, bytes: field.data.count % 16)
            var reader = BinaryReader(field.data)
            var values: [SpecialReference] = []
            values.reserveCapacity(field.data.count / 16)
            for _ in 0 ..< (field.data.count / 16) {
                try values.append(SpecialReference(
                    type: FormID(reader.readUInt32()),
                    reference: FormID(reader.readUInt32()),
                    worldOrCell: FormID(reader.readUInt32()),
                    gridY: Int16(bitPattern: reader.readUInt16()),
                    gridX: Int16(bitPattern: reader.readUInt16())
                ))
            }
            return values
        }

        private mutating func formIDs(_ field: ESMField) throws -> [FormID] {
            skipped.noteTail(field.type, bytes: field.data.count % 4)
            var reader = BinaryReader(field.data)
            var values: [FormID] = []
            values.reserveCapacity(field.data.count / 4)
            for _ in 0 ..< (field.data.count / 4) {
                try values.append(FormID(reader.readUInt32()))
            }
            return values
        }

        private mutating func cells(_ field: ESMField) throws -> WorldspaceCells {
            guard field.data.count >= 4 else {
                throw ESMError.malformed("\(field.type) location-cell array is truncated")
            }
            skipped.noteTail(field.type, bytes: (field.data.count - 4) % 4)
            var reader = BinaryReader(field.data)
            let worldspace = try FormID(reader.readUInt32())
            var values: [WorldspaceCells.Grid] = []
            values.reserveCapacity((field.data.count - 4) / 4)
            for _ in 0 ..< ((field.data.count - 4) / 4) {
                try values.append(WorldspaceCells.Grid(
                    y: Int16(bitPattern: reader.readUInt16()),
                    x: Int16(bitPattern: reader.readUInt16())
                ))
            }
            return WorldspaceCells(worldspace: worldspace, cells: values)
        }

        private mutating func parents(_ field: ESMField) throws -> [EnableParent] {
            skipped.noteTail(field.type, bytes: field.data.count % 12)
            var reader = BinaryReader(field.data)
            var values: [EnableParent] = []
            values.reserveCapacity(field.data.count / 12)
            for _ in 0 ..< (field.data.count / 12) {
                let reference = try FormID(reader.readUInt32())
                let parent = try FormID(reader.readUInt32())
                let flags = try reader.readUInt8()
                reader.skip(3)
                values.append(EnableParent(reference: reference, parent: parent, flags: flags))
            }
            return values
        }
    }
}
