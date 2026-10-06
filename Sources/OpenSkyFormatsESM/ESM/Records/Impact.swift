// IPDS impact data set and IPCT impact: the chain from a footstep to a sound.
// IPDS pairs each MATT material with an IPCT. Only the audio members are
// decoded. Layout and sources: docs/formats/footstep.md.

import Foundation
import OpenSkyFormatsCore

/// One IPCT: what a hit leaves behind and how it sounds. xEdit dev-4.1.6 `IPCT`.
nonisolated public struct Impact: Equatable, Sendable {
    /// DATA. The first four members are required; the rest arrived later.
    public struct Effect: Equatable, Sendable {
        public let duration: Float
        /// 0 surface normal, 1 projectile vector, 2 projectile reflection.
        public let orientation: UInt32
        public let angleThreshold: Float
        public let placementRadius: Float
        public let soundLevel: UInt32?
        /// Bit 0: no decal data.
        public let flags: UInt8?
        /// 0 default, 1 destroy, 2 bounce, 3 impale, 4 stick.
        public let result: UInt8?

        init(_ reader: inout BinaryReader) throws {
            duration = try reader.readFloat32()
            orientation = try reader.readUInt32()
            angleThreshold = try reader.readFloat32()
            placementRadius = try reader.readFloat32()
            soundLevel = reader.bytesRemaining >= 4 ? try reader.readUInt32() : nil
            flags = reader.bytesRemaining >= 1 ? try reader.readUInt8() : nil
            result = reader.bytesRemaining >= 1 ? try reader.readUInt8() : nil
        }
    }

    public let formID: FormID
    public let editorID: String?
    public let model: ModelData?
    public let effect: Effect?
    public let decal: DecalData?
    /// DNAM/ENAM — the TXSTs the decal draws.
    public let textureSet: FormID?
    public let secondaryTextureSet: FormID?
    /// SNAM -> SNDR. The impact's primary sound; nil when absent or null.
    public let sound: FormID?
    /// NAM1 -> SNDR. The secondary sound vanilla layers under a few impacts;
    /// nil when absent or null.
    public let secondarySound: FormID?
    /// NAM2 -> HAZD left at the hit.
    public let hazard: FormID?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var rest = try RecordFields(record: record, type: "IPCT")
        formID = rest.formID
        editorID = rest.editorID()
        model = rest.model()
        effect = rest.read("DATA") { try Effect(&$0) }
        decal = rest.read("DODT") { try DecalData(&$0) }
        textureSet = rest.formID("DNAM")
        secondaryTextureSet = rest.formID("ENAM")
        sound = rest.formID("SNAM")
        secondarySound = rest.formID("NAM1")
        hazard = rest.formID("NAM2")
        skipped = rest.finish()
    }
}

/// One IPDS: the material-to-impact table an impact source is resolved
/// through.
nonisolated public struct ImpactDataSet: Equatable, Sendable {
    /// One PNAM pair.
    public struct Entry: Equatable, Sendable {
        /// MATT material type the pair applies to.
        public let material: FormID
        /// IPCT to play on that material.
        public let impact: FormID
    }

    public let formID: FormID
    public let editorID: String?
    /// The PNAM pairs in record order. Vanilla sets carry one pair per material
    /// the Creation Kit knows about — around 70 of them — and most name the
    /// same impact throughout.
    public let entries: [Entry]
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "IPDS" else {
            throw ESMError.malformed("expected IPDS record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var entries: [Entry] = []
        var skipped = FieldTally()
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "PNAM":
                // A short or odd-sized PNAM is skipped rather than throwing:
                // one malformed pair must not cost the whole table.
                guard field.data.count >= 8 else { break }
                let material = try FormID(reader.readUInt32())
                let impact = try FormID(reader.readUInt32())
                guard !impact.isNull else { break }
                entries.append(Entry(material: material, impact: impact))
            default:
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped
        self.editorID = editorID
        self.entries = entries
    }

    /// Test seam.
    public init(formID: FormID, editorID: String?, entries: [Entry]) {
        self.formID = formID
        self.editorID = editorID
        self.entries = entries
        skipped = FieldTally()
    }

    /// The impact for `material`, or the representative one when the surface is
    /// unknown: the most frequent IPCT in the table, ties broken by record
    /// order. Footsteps use it until collision materials exist.
    public func impact(for material: FormID?) -> FormID? {
        if let material, let match = entries.first(where: { $0.material == material }) {
            return match.impact
        }
        var counts: [UInt32: Int] = [:]
        var best: FormID?
        var bestCount = 0
        for entry in entries {
            let count = (counts[entry.impact.rawValue] ?? 0) + 1
            counts[entry.impact.rawValue] = count
            if count > bestCount {
                bestCount = count
                best = entry.impact
            }
        }
        return best
    }
}
