// M19 magic summaries kept outside RecordTextDump's capped dispatch switch.
// The formatter feeds both `openskycli record` and the Asset Browser.

import Foundation

nonisolated extension RecordTextDump {
    struct MagicInspectorContext {
        let keywordStore: KeywordStore
        let formListStore: FormListStore
        let magicEffectStore: MagicEffectStore
        let spellStore: SpellStore
        let sourcePlugin: String
    }

    /// The magic stores a summary needs to name what a record points at: MGEF
    /// for EFID links, SPEL/SCRL for the spell a book teaches or a weapon's
    /// critical applies.
    struct MagicContext {
        let effects: MagicEffectStore
        let spells: SpellStore
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
            magicContext: MagicContext(
                effects: context.magicEffectStore,
                spells: context.spellStore,
                sourcePlugin: context.sourcePlugin
            )
        )
    }

    static func magicSummary(
        record: ESMRecord,
        localized: Bool,
        keywordContext: KeywordContext?,
        magicContext: MagicContext?
    ) -> String? {
        switch record.type {
        case "MGEF": magicEffectSummary(record, localized, keywordContext)
        case "SPEL": spellSummary(record, localized, magicContext)
        case "SCRL": scrollSummary(record, localized, magicContext)
        default: nil
        }
    }

    private static func magicEffectSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ keywordContext: KeywordContext?
    ) -> String? {
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

    private static func spellSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: MagicContext?
    ) -> String? {
        guard let spell = try? Spell(record: record, localized: localized) else { return nil }
        return castingSummary(.spell(spell), context: context)
    }

    private static func scrollSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: MagicContext?
    ) -> String? {
        guard let scroll = try? Scroll(record: record, localized: localized) else { return nil }
        let value = String(
            format: ", value %d, weight %.2f",
            Int(scroll.itemValue.value),
            scroll.itemValue.weight
        )
        return castingSummary(.scroll(scroll), context: context, suffix: value)
    }

    /// Header line plus the effect table, shared by SPEL and SCRL. Without a
    /// magic context the effects still print, by raw FormID and without costs,
    /// because the base costs live in the MGEF definitions.
    private static func castingSummary(
        _ record: MagicCastingRecord,
        context: MagicContext?,
        suffix: String = ""
    ) -> String {
        var line = "decoded \(record.recordType): editorID \(record.editorID ?? "-"), "
            + "name \(display(record.name))"
        if let data = record.data {
            line += String(
                format: ", type %@, casting %@, delivery %@, charge time %.2f, range %.1f",
                data.type.description,
                data.castingType.description,
                data.delivery.description,
                data.chargeTime,
                data.range
            )
        } else {
            line += ", SPIT malformed"
        }
        line += suffix
        guard let context else {
            let names = record.effects.map(\.effect.description)
            return line + ", \(names.count) effects [\(names.joined(separator: ", "))]"
                + ", skipped \(record.skipped.total)"
        }
        let effects = SpellStore.resolvedEffects(
            of: record,
            fromPlugin: context.sourcePlugin,
            effects: context.effects
        )
        let cost = SpellStore.cost(of: record, effects: effects)
        line += ", cost \(costText(cost)), skipped \(record.skipped.total)"
        return ([line] + effectTable(effects)).joined(separator: "\n")
    }

    private static func costText(_ cost: SpellCostResult) -> String {
        let source = cost.isManual ? "manual" : "auto-calc"
        let unresolved = cost.unresolvedEffects > 0
            ? ", \(cost.unresolvedEffects) unresolved"
            : ""
        return String(
            format: "%d (%@, formula %.2f%@)",
            Int(cost.cost),
            source,
            cost.autoCalculated,
            unresolved
        )
    }

    private static func effectTable(_ effects: [ResolvedSpellEffect]) -> [String] {
        ["  effects (\(effects.count)):"] + effects.map { effect in
            String(
                format: "    %@ — magnitude %.2f, area %d, duration %ds, cost %.2f",
                effect.displayName,
                effect.item.magnitude,
                Int(effect.item.area),
                Int(effect.item.duration),
                effect.cost
            )
        }
    }

    private static func display(_ value: LString?) -> String {
        switch value {
        case let .inline(text): "\"\(text)\""
        case let .tableID(id): "string #\(id)"
        case nil: "-"
        }
    }
}
