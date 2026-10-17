// A spell as the subject of a perk's spell condition tab. A SPEL has no `KWDA`, so
// `HasKeyword` reads the keywords of its effects, as `EPMagic_SpellHasKeyword` does.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension SpellStore {
    public func conditionSubject(of spell: ResolvedSpell) -> ConditionFormSubject {
        let keywords = spell.effects.compactMap(\.effect).flatMap { effect in
            effect.effect.keywords.keywords.compactMap { keyword in
                resolvedID(keyword, fromPlugin: effect.sourcePlugin)
                    .map(ReferenceKey.init(resolved:))
            }
        }
        return ConditionFormSubject(id: spell.id, effectKeywords: Set(keywords))
    }
}
