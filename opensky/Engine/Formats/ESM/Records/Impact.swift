// IPDS impact-data-set and IPCT impact records (issue #352). Between a
// footstep and a sound sits the impact chain: FSTP.DATA names an IPDS, the
// IPDS pairs each material type (MATT) with the IPCT to play on it, and the
// IPCT names the sound descriptors.
//
// References: UESP "Skyrim Mod:Mod File Format/IPDS" and ".../IPCT"; xEdit
// dev-4.1.6 wbDefinitionsTES5.pas:
//   wbRecord(IPDS, 'Impact Data Set', [
//     wbEDID, wbRArray('Data', wbRStruct('', [
//       wbFormIDCk(PNAM, 'Material', [MATT]) ... ]))
//   ]);
// with PNAM carrying the material FormID and the impact FormID as one 8-byte
// pair. Only the members the audio side needs are decoded here: the visual
// half of an impact (model, decal, texture sets, hazard) waits for a consumer.

import Foundation

/// One IPCT, reduced to its sound links. The decal, model, and hazard members
/// are deliberately not decoded: nothing draws an impact yet, and a field this
/// decoder does not read cannot go stale against the spec.
nonisolated struct Impact: Equatable, Sendable {
    let formID: FormID
    let editorID: String?
    /// SNAM -> SNDR. The impact's primary sound; nil when absent or null.
    let sound: FormID?
    /// NAM1 -> SNDR. The secondary sound vanilla layers under a few impacts;
    /// nil when absent or null.
    let secondarySound: FormID?

    init(record: ESMRecord) throws {
        guard record.type == "IPCT" else {
            throw ESMError.malformed("expected IPCT record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var sound: FormID?
        var secondarySound: FormID?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "SNAM":
                sound = try Self.readLink(&reader, size: field.data.count)
            case "NAM1":
                secondarySound = try Self.readLink(&reader, size: field.data.count)
            default:
                break
            }
        }
        self.editorID = editorID
        self.sound = sound
        self.secondarySound = secondarySound
    }

    private static func readLink(
        _ reader: inout BinaryReader,
        size: Int
    ) throws -> FormID? {
        guard size == 4 else { return nil }
        let id = try FormID(reader.readUInt32())
        return id.isNull ? nil : id
    }
}

/// One IPDS: the material-to-impact table an impact source is resolved
/// through.
nonisolated struct ImpactDataSet: Equatable, Sendable {
    /// One PNAM pair.
    struct Entry: Equatable, Sendable {
        /// MATT material type the pair applies to.
        let material: FormID
        /// IPCT to play on that material.
        let impact: FormID
    }

    let formID: FormID
    let editorID: String?
    /// The PNAM pairs in record order. Vanilla sets carry one pair per material
    /// the Creation Kit knows about — around 70 of them — and most name the
    /// same impact throughout.
    let entries: [Entry]

    init(record: ESMRecord) throws {
        guard record.type == "IPDS" else {
            throw ESMError.malformed("expected IPDS record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var entries: [Entry] = []
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
                break
            }
        }
        self.editorID = editorID
        self.entries = entries
    }

    /// Test seam.
    init(formID: FormID, editorID: String?, entries: [Entry]) {
        self.formID = formID
        self.editorID = editorID
        self.entries = entries
    }

    /// The impact to play on `material`, or the representative one when the
    /// caller does not know which surface was struck.
    ///
    /// OpenSky has no per-triangle collision material yet (issue #358), so
    /// every footstep asks for the representative impact. That
    /// is the most frequently paired IPCT in the table, with ties broken by
    /// record order — a measurement of what the authored table mostly says
    /// rather than a hardcoded material. A set whose entries all agree, which
    /// is the common vanilla case, returns that one impact exactly.
    func impact(for material: FormID?) -> FormID? {
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
