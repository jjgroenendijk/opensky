// ARTO art object: a model that a magic effect attaches to a caster, a target,
// or an enchanted item. Layout and sources: docs/formats/art-objects.md.

import Foundation
import OpenSkyFormatsCore

/// DNAM, a uint32. An unknown value keeps its number.
nonisolated public enum ArtType: Equatable, Sendable {
    case magicCasting
    case magicHitEffect
    case enchantmentEffect
    case unknown(UInt32)

    public init(rawValue: UInt32) {
        self = switch rawValue {
        case 0: .magicCasting
        case 1: .magicHitEffect
        case 2: .enchantmentEffect
        default: .unknown(rawValue)
        }
    }

    public var rawValue: UInt32 {
        switch self {
        case .magicCasting: 0
        case .magicHitEffect: 1
        case .enchantmentEffect: 2
        case let .unknown(value): value
        }
    }
}

nonisolated public struct ArtObject: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let bounds: ObjectBounds?
    /// MODL, relative to `Data/meshes`.
    public let modelPath: String?
    /// Nil when the record has no readable DNAM.
    public let artType: ArtType?
    public let skipped: ItemFieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "ARTO" else {
            throw ESMError.malformed("expected ARTO record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var bounds: ObjectBounds?
        var modelPath: String?
        var artType: ArtType?
        var tally = ItemFieldTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "OBND": bounds = try ObjectBounds(field: field)
                case "MODL": modelPath = try reader.readZString()
                case "DNAM": artType = try ArtType(rawValue: reader.readUInt32())
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        self.bounds = bounds
        self.modelPath = modelPath
        self.artType = artType
        skipped = tally
    }
}
