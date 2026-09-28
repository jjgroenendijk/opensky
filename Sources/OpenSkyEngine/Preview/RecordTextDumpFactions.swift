// M21 faction summaries — FACT — kept out of RecordTextDump's capped dispatch
// switch. The formatter feeds both `openskycli record` and the Asset Browser.

import Foundation

nonisolated extension RecordTextDump {
    /// FACT: the identity and flag line, then the crime values, the rank table,
    /// the interfaction relations and the raw vendor block, each printed only
    /// when the record carries it.
    static func factionSummary(_ record: ESMRecord, _ localized: Bool) -> String? {
        guard record.type == "FACT" else { return nil }
        guard let faction = try? Faction(record: record, localized: localized) else { return nil }
        var lines = [
            "decoded FACT: editorID \(faction.editorID ?? "-"), "
                + "name \(nameText(faction.name)), "
                + "flags \(flagText(faction.flags)), "
                + "skipped \(faction.skipped.total)"
        ]
        lines.append(contentsOf: crimeLines(faction.crimeValues))
        lines.append(contentsOf: crimeLinkLines(faction))
        lines.append(contentsOf: rankLines(faction.ranks))
        lines.append(contentsOf: relationLines(faction.relations))
        lines.append(contentsOf: vendorLines(faction))
        return lines.joined(separator: "\n")
    }

    /// Set bits by name, with any bit the spec does not name kept as a raw
    /// mask so an unrecognized flag stays visible.
    private static func flagText(_ flags: Faction.Flags) -> String {
        let named: [(Faction.Flags, String)] = [
            (.hiddenFromNPC, "hidden from NPC"),
            (.specialCombat, "special combat"),
            (.trackCrime, "track crime"),
            (.ignoreMurder, "ignore murder"),
            (.ignoreAssault, "ignore assault"),
            (.ignoreStealing, "ignore stealing"),
            (.ignoreTrespass, "ignore trespass"),
            (.doNotReportCrimesAgainstMembers, "do not report crimes against members"),
            (.crimeGoldUseDefaults, "crime gold use defaults"),
            (.ignorePickpocket, "ignore pickpocket"),
            (.vendor, "vendor"),
            (.canBeOwner, "can be owner"),
            (.ignoreWerewolf, "ignore werewolf")
        ]
        var set = named.filter { flags.contains($0.0) }.map(\.1)
        let known = named.reduce(into: Faction.Flags()) { $0.insert($1.0) }
        let unnamed = flags.rawValue & ~known.rawValue
        if unnamed != 0 {
            set.append(String(format: "unknown 0x%08X", unnamed))
        }
        return "0x\(String(format: "%08X", flags.rawValue)) [\(set.joined(separator: ", "))]"
    }

    private static func crimeLines(_ values: Faction.CrimeValues?) -> [String] {
        guard let values else { return [] }
        var line = "  crime: arrest \(values.arrest), attack on sight \(values.attackOnSight), "
            + "murder \(values.murder), assault \(values.assault), "
            + "trespass \(values.trespass), pickpocket \(values.pickpocket)"
        if let multiplier = values.stealMultiplier {
            line += String(format: ", steal multiplier %.4f", multiplier)
        }
        if let escape = values.escape, let werewolf = values.werewolf {
            line += ", escape \(escape), werewolf \(werewolf)"
        }
        return [line]
    }

    private static func crimeLinkLines(_ faction: Faction) -> [String] {
        let links: [(String, FormID?)] = [
            ("jail marker", faction.exteriorJailMarker),
            ("follower wait marker", faction.followerWaitMarker),
            ("evidence chest", faction.evidenceChest),
            ("player inventory", faction.playerInventoryContainer),
            ("shared crime list", faction.sharedCrimeFactionList),
            ("jail outfit", faction.jailOutfit)
        ]
        let present = links.compactMap { name, id in
            id.map { "\(name) \($0)" }
        }
        return present.isEmpty ? [] : ["  crime links: \(present.joined(separator: ", "))"]
    }

    private static func rankLines(_ ranks: [Faction.Rank]) -> [String] {
        guard !ranks.isEmpty else { return [] }
        return ["  ranks (\(ranks.count)):"] + ranks.prefix(fieldPrintCap).map { rank in
            "    #\(rank.index) male \(nameText(rank.maleTitle)), "
                + "female \(nameText(rank.femaleTitle))"
        }
    }

    private static func relationLines(_ relations: [Faction.Relation]) -> [String] {
        guard !relations.isEmpty else { return [] }
        return ["  relations (\(relations.count)):"]
            + relations.prefix(fieldPrintCap).map { relation in
                "    \(relation.faction) \(relation.reaction), modifier \(relation.modifier)"
            }
    }

    private static func vendorLines(_ faction: Faction) -> [String] {
        var lines: [String] = []
        if let values = faction.vendorValues {
            lines.append(
                "  vendor: hours \(values.startHour)-\(values.endHour), "
                    + "radius \(values.radius), "
                    + "only buys stolen \(values.onlyBuysStolenItems), "
                    + "not sell/buy \(values.notSellBuy)"
            )
        }
        let links = [
            faction.vendorBuySellList.map { "buy/sell list \($0)" },
            faction.merchantContainer.map { "merchant container \($0)" }
        ].compactMap(\.self)
        if !links.isEmpty {
            lines.append("  vendor links: \(links.joined(separator: ", "))")
        }
        if let location = faction.vendorLocation {
            lines.append(
                "  vendor location: type \(location.type), "
                    + "value 0x\(String(format: "%08X", location.value)), "
                    + "radius \(location.radius)"
            )
        }
        if !faction.vendorConditions.isEmpty {
            lines.append("  vendor conditions: \(faction.vendorConditions.conditions.count)")
        }
        return lines
    }
}
