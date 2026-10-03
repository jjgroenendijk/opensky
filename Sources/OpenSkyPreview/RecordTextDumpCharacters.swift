// Decoded views of the character records: head parts, colors, eyes, body
// parts, and the idle records. See docs/formats/head-parts.md,
// docs/formats/body-parts.md, and docs/formats/idle.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension RecordTextDump {
    static func characterSummary(_ record: ESMRecord, _ localized: Bool) throws -> String? {
        switch record.type {
        case "HDPT": try headPartText(HeadPart(record: record, localized: localized))
        case "CLFM": try colorText(ColorForm(record: record, localized: localized))
        case "EYES": try eyesText(Eyes(record: record, localized: localized))
        case "BPTD": try bodyPartText(BodyPartData(record: record, localized: localized))
        default: try idleSummary(record)
        }
    }

    private static func idleSummary(_ record: ESMRecord) throws -> String? {
        switch record.type {
        case "IDLE":
            let idle = try IdleAnimation(record: record)
            return "decoded IDLE: editorID \(idle.editorID ?? "-"), "
                + "behavior \(idle.fileName ?? "-"), event \(idle.animationEvent ?? "-"), "
                + "parent \(idle.parent?.description ?? "-"), "
                + "conditions \(idle.conditions.count)"
        case "ANIO":
            let object = try AnimatedObject(record: record)
            return "decoded ANIO: editorID \(object.editorID ?? "-"), "
                + "model \(object.model?.path ?? "-"), unload \(object.unloadEvent ?? "-")"
        case "IDLM":
            let marker = try IdleMarker(record: record)
            return "decoded IDLM: editorID \(marker.editorID ?? "-"), "
                + "idles \(marker.idles.count), flags \(marker.flags.map { String($0) } ?? "-"), "
                + "timer \(marker.idleTimer.map { String($0) } ?? "-")"
        default:
            return nil
        }
    }

    private static func headPartText(_ part: HeadPart) -> String {
        "decoded HDPT: editorID \(part.editorID ?? "-"), "
            + "type \(part.partType.map { "\($0)" } ?? "-"), model \(part.model?.path ?? "-"), "
            + "extra parts \(part.extraParts.count), "
            + "texture set \(part.textureSet?.description ?? "-"), "
            + "color \(part.color?.description ?? "-"), "
            + "races \(part.validRaces?.description ?? "-")"
    }

    private static func colorText(_ color: ColorForm) -> String {
        let rgba = color.color.map { "\($0.x) \($0.y) \($0.z) \($0.w)" } ?? "-"
        return "decoded CLFM: editorID \(color.editorID ?? "-"), name \(nameText(color.name)), "
            + "color \(rgba), playable \(color.isPlayable)"
    }

    private static func eyesText(_ eyes: Eyes) -> String {
        "decoded EYES: editorID \(eyes.editorID ?? "-"), name \(nameText(eyes.name)), "
            + "texture \(eyes.texturePath ?? "-"), flags \(eyes.flags)"
    }

    private static func bodyPartText(_ data: BodyPartData) -> String {
        "decoded BPTD: editorID \(data.editorID ?? "-"), skeleton \(data.model?.path ?? "-"), "
            + "parts \(data.parts.count)"
    }
}
