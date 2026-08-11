// HDPT head-part association data used by FaceGen expression morphs.
//
// Reference: xEdit TES5 definitions, HDPT record on dev-4.1.6. NAM0 names
// the following NAM1 path as race morph (0), expression TRI (1), or chargen
// morph (2). OpenSky decodes only the fields needed to pair a baked FaceGen
// BSDynamicTriShape with its expression container.
// https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas

import Foundation

nonisolated struct HeadPart: Equatable {
    nonisolated enum MorphKind: UInt32, Equatable {
        case race = 0
        case expression = 1
        case chargen = 2
    }

    nonisolated struct MorphPath: Equatable {
        let kind: MorphKind
        let path: String
    }

    let formID: FormID
    let editorID: String?
    let morphPaths: [MorphPath]

    var expressionMorphPath: String? {
        morphPaths.first { $0.kind == .expression }?.path
    }

    init(record: ESMRecord) throws {
        guard record.type == "HDPT" else {
            throw ESMError.malformed("expected HDPT record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var pendingKind: MorphKind?
        var morphPaths: [MorphPath] = []
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "NAM0":
                pendingKind = try MorphKind(rawValue: reader.readUInt32())
            case "NAM1":
                let path = try reader.readZString()
                if let kind = pendingKind {
                    morphPaths.append(MorphPath(kind: kind, path: path))
                }
                pendingKind = nil
            default:
                break
            }
        }
        self.editorID = editorID
        self.morphPaths = morphPaths
    }
}
