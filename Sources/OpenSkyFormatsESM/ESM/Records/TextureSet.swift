// TXST texture set: eight texture slots, decal data, and flags.
// Layout and sources: docs/formats/land.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct TextureSet: Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public static let noSpecularMap = Flags(rawValue: 0x0001)
        public static let faceGenTextures = Flags(rawValue: 0x0002)
        public static let modelSpaceNormalMap = Flags(rawValue: 0x0004)
    }

    /// The TX00-TX07 slot names, from xEdit dev-4.1.6.
    public static let slotTypes: [FourCC] = [
        "TX00", "TX01", "TX02", "TX03", "TX04", "TX05", "TX06", "TX07"
    ]

    public internal(set) var formID: FormID
    public let editorID: String?
    public let bounds: ObjectBounds?
    /// Texture paths relative to Data/, by slot: diffuse, normal/gloss,
    /// environment mask or subsurface tint, glow or detail, height,
    /// environment, multilayer, backlight or specular. Nil for an empty slot.
    public let paths: [String?]
    public let decal: DecalData?
    public let flags: Flags
    public let skipped: FieldTally

    /// TX00 — diffuse map path (e.g. "textures\\...\\x.dds").
    public var diffusePath: String? {
        paths[0]
    }

    /// TX01 — normal/gloss map path.
    public var normalPath: String? {
        paths[1]
    }

    public init(record: ESMRecord) throws {
        var rest = try RecordFields(record: record, type: "TXST")
        formID = rest.formID
        editorID = rest.editorID()
        bounds = rest.bounds()
        paths = Self.slotTypes.map { rest.zstring($0) }
        decal = rest.read("DODT") { try DecalData(&$0) }
        flags = Flags(rawValue: rest.uint16("DNAM") ?? 0)
        skipped = rest.finish()
    }
}
