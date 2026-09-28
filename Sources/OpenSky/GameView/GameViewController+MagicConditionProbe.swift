// The Spellcasting panel's condition probe (issue #474, roadmap item 19.11):
// the eight magic condition functions evaluated against the player, one line
// each.
//
// This is the surface that makes the registrations verifiable without a CLI
// command. A reader who has just readied a spell and wants to know what a
// condition would say about it reads it here, beside the hand it is in, rather
// than under Runtime State — whose selectable lists are MUST records, which
// author no magic conditions at all.
//
// Every probe goes through `ConditionProbe` over a real `ConditionContext`,
// built by `magicConditionResolution()`, so the line a reader sees comes out of
// the same registry and the same function body a quest's condition would reach.
// A function that cannot answer prints the reason
// `RuntimeStateConditionRunner` gives it, which is what keeps a gap
// distinguishable from a zero.

import AppKit

extension GameViewController {
    /// One probe: which function to run and how to spell its parameter.
    private struct MagicProbe {
        let index: UInt16
        let name: String
        /// Parameter word, and the text describing what it names.
        let parameter: UInt32
        let parameterText: String
    }

    /// The eight functions, in registry order, against the player.
    ///
    /// The record-taking functions are probed against the *readied* spell and
    /// its first effect, because those are the two records a reader of this
    /// panel can see: probing a fixed FormID would print a line about a spell
    /// nobody chose.
    func magicConditionLines() -> [String] {
        guard let runtime = casting.runtime else { return [] }
        let book = runtime.spellbook.state(of: .player)
        let readied = book.spell(in: .right) ?? book.spell(in: .left)
        let record = readied.flatMap(runtime.spellbook.record)
        let context = magicConditionContext()
        return magicProbes(spell: record).map { probe in
            probeLine(probe, context: context)
        }
    }

    private func magicProbes(spell record: ResolvedSpell?) -> [MagicProbe] {
        let spellID = record?.id.objectID ?? 0
        let effectID = record?.record.effects.first?.effect.rawValue ?? 0
        let spellName = record?.displayName ?? "no readied spell"
        return [
            MagicProbe(
                index: 214, name: "HasMagicEffect",
                parameter: effectID, parameterText: "first effect of \(spellName)"
            ),
            MagicProbe(
                index: 223, name: "IsSpellTarget",
                parameter: spellID, parameterText: spellName
            ),
            MagicProbe(
                index: 264, name: "HasSpell",
                parameter: spellID, parameterText: spellName
            ),
            MagicProbe(
                index: 570, name: "HasEquippedSpell",
                parameter: 1, parameterText: "right hand"
            ),
            MagicProbe(
                index: 571, name: "GetCurrentCastingType",
                parameter: 1, parameterText: "right hand"
            ),
            MagicProbe(
                index: 572, name: "GetCurrentDeliveryType",
                parameter: 1, parameterText: "right hand"
            ),
            MagicProbe(index: 632, name: "IsCasting", parameter: 0, parameterText: "none"),
            MagicProbe(
                index: 699, name: "HasMagicEffectKeyword",
                parameter: 0, parameterText: "keyword 0"
            )
        ]
    }

    /// The player as both subject and target, with the live magic seam and
    /// nothing else the magic functions read.
    private func magicConditionContext() -> ConditionContext {
        ConditionContext(
            magic: magicConditionResolution(),
            subject: .player,
            target: .player
        )
    }

    /// One probe run through `ConditionProbe`, which is the same registry and
    /// the same function bodies a record's condition goes through.
    private func probeLine(_ probe: MagicProbe, context: ConditionContext) -> String {
        let value = ConditionProbe.text(
            of: probe.index, parameter1: probe.parameter, in: context
        )
        return "\(probe.name)(\(probe.parameterText)) -> \(value)"
    }
}
