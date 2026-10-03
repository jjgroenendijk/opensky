// Resolves the records a visual effect can be built from into one look: an
// `RFCT` names an `ARTO` model and an `EFSH` membrane; an `EFSH`, `ARTO`, or
// `ADDN` alone gives half of that. See docs/rendering/visual-effects.md.

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension EffectRecordStore {
    /// The look of an `RFCT`, `EFSH`, `ADDN`, or `ARTO`, or nil for any other record or an
    /// effect that would draw nothing.
    public func visualEffectSpec(_ key: ReferenceKey) -> VisualEffectSpec? {
        let spec: VisualEffectSpec? = switch recordType(key).map({ "\($0)" }) {
        case "RFCT":
            visualEffects.record(key).map { resolved in
                VisualEffectSpec(
                    name: resolved.record.editorID ?? "\(key)",
                    artModel: resolve(resolved.record.effectArt, from: resolved)
                        .flatMap(artModel),
                    membrane: resolve(resolved.record.shader, from: resolved).flatMap(membrane)
                )
            }
        case "EFSH":
            effectShaders.record(key).map {
                VisualEffectSpec(
                    name: $0.record.editorID ?? "\(key)", artModel: nil,
                    membrane: MembraneLook(shader: $0.record)
                )
            }
        case "ADDN":
            addonNodes.record(key).map {
                VisualEffectSpec(
                    name: $0.record.editorID ?? "\(key)", artModel: $0.record.model?.path,
                    membrane: nil
                )
            }
        case "ARTO":
            artObjects.record(key).map {
                VisualEffectSpec(
                    name: $0.record.editorID ?? "\(key)", artModel: $0.record.modelPath,
                    membrane: nil
                )
            }
        default:
            nil
        }
        return spec?.isVisible == true ? spec : nil
    }

    private func artModel(_ key: ReferenceKey) -> String? {
        artObjects.record(key)?.record.modelPath
    }

    private func membrane(_ key: ReferenceKey) -> MembraneLook? {
        effectShaders.record(key).flatMap { MembraneLook(shader: $0.record) }
    }
}
