// M19 magic summaries kept outside RecordTextDump's capped dispatch switch.
// The formatter feeds both `openskycli record` and the Asset Browser.

import Foundation

nonisolated extension RecordTextDump {
    struct MagicInspectorContext {
        let keywordStore: KeywordStore
        let formListStore: FormListStore
        let magicEffectStore: MagicEffectStore
        let sourcePlugin: String
    }

    struct MagicEffectContext {
        let store: MagicEffectStore
        let sourcePlugin: String
    }

    static func dump(
        record: ESMRecord,
        localized: Bool,
        magicInspectorContext context: MagicInspectorContext
    ) -> String {
        dump(
            record: record,
            localized: localized,
            keywordContext: KeywordContext(
                store: context.keywordStore,
                sourcePlugin: context.sourcePlugin
            ),
            formListContext: FormListContext(
                store: context.formListStore,
                sourcePlugin: context.sourcePlugin
            ),
            magicEffectContext: MagicEffectContext(
                store: context.magicEffectStore,
                sourcePlugin: context.sourcePlugin
            )
        )
    }

    static func magicSummary(
        record: ESMRecord,
        localized: Bool,
        keywordContext: KeywordContext?
    ) -> String? {
        guard record.type == "MGEF" else { return nil }
        guard let effect = try? MagicEffect(record: record, localized: localized) else {
            return nil
        }
        let name = display(effect.name)
        let keywords = if let keywordContext {
            effect.keywords.displayStrings(
                fromPlugin: keywordContext.sourcePlugin,
                using: keywordContext.store
            )
        } else {
            effect.keywords.keywords.map(\.description)
        }
        guard let data = effect.data else {
            return "decoded MGEF: editorID \(effect.editorID ?? "-"), name \(name), "
                + "DATA malformed, skipped \(effect.skipped.total)"
        }
        return String(
            format: "decoded MGEF: editorID %@, name %@, archetype %@, casting %@, "
                + "delivery %@, cost %.3f, related actor value %@, resistance %@, "
                + "keywords [%@], skipped %d",
            effect.editorID ?? "-",
            name,
            data.archetype.description,
            data.castingType.description,
            data.delivery.description,
            data.baseCost,
            ActorValueIdentity.description(of: data.relatedActorValue),
            ActorValueIdentity.description(of: data.resistanceActorValue),
            keywords.joined(separator: ", "),
            effect.skipped.total
        )
    }

    private static func display(_ value: LString?) -> String {
        switch value {
        case let .inline(text): "\"\(text)\""
        case let .tableID(id): "string #\(id)"
        case nil: "-"
        }
    }
}
