// Which `ATKD` attacks an actor uses: its own, merged with its `ATKR` race's, through
// the Attack Data template flag, else its race's. Rules: docs/engine/attack-data.md.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public enum ActorAttackList {
    /// `own` merged with `attackRace`'s list, or nil when there is neither. An own
    /// attack the attack race lacks goes; when the counts still differ, each attack-race
    /// entry the own list lacks is added. An own entry wins over the race's.
    public static func merge(own: [RaceAttack], attackRace: [RaceAttack]?) -> [RaceAttack]? {
        guard let attackRace else { return own.isEmpty ? nil : own }
        var merged = own.filter { attack in
            attackRace.contains { other in attack.event.map(other.starts(with:)) ?? false }
        }
        if merged.count != attackRace.count {
            for attack in attackRace where !merged.contains(where: { kept in
                attack.event.map(kept.starts(with:)) ?? false
            }) {
                merged.append(attack)
            }
        }
        return merged
    }

    /// The attack `event` starts in `list`, or nil when none does.
    public static func attack(_ list: [RaceAttack], event: String) -> RaceAttack.Properties? {
        list.first { $0.starts(with: event) }?.properties
    }
}

nonisolated extension ActorValueResolver {
    /// A race's own attacks, merged with its `ATKR` race's.
    public func raceAttacks(_ race: FormID) -> [RaceAttack] {
        guard let details = races[race.rawValue]?.details else { return [] }
        return ActorAttackList.merge(
            own: details.attacks,
            attackRace: details.attackRace.flatMap { races[$0.rawValue]?.details.attacks }
        ) ?? []
    }

    /// The attacks of an actor of `base` whose race is now `race`. A list that comes
    /// from the record's race follows a race change, unless the new race rebuilds its
    /// head on the change, as the werewolf does.
    public func attacks(base: FormID, race current: FormID?) -> [RaceAttack] {
        guard let (npcs, _) = attempt({ try templates.resolveChain(base: base) }) else {
            return current.map(raceAttacks) ?? []
        }
        if let own = ownAttacks(npcs, from: 0) {
            return own
        }
        let recordRace = attempt { try templates.resolve(base: base) }?.race.value
        let keepsOld = current.flatMap { races[$0.rawValue]?.flags }.map {
            !$0.isDisjoint(with: [.rebuildsHeadWithDefaults, .rebuildsHeadFromRace])
        } ?? false
        let race = keepsOld ? recordRace ?? current : current ?? recordRace
        return race.map(raceAttacks) ?? []
    }

    /// The list of `npcs[index]`: its template's when the Attack Data flag delegates
    /// and the template has its own, else its own merge.
    private func ownAttacks(_ npcs: [ActorBase], from index: Int) -> [RaceAttack]? {
        let npc = npcs[index]
        if
            npc.template != nil, npc.templateFlags.contains(.useAttackData),
            index < npcs.count - 1,
            let inherited = ownAttacks(npcs, from: index + 1)
        {
            return inherited
        }
        return ActorAttackList.merge(
            own: npc.details.attacks,
            attackRace: npc.details.attackRace.flatMap { races[$0.rawValue]?.details.attacks }
        )
    }
}
