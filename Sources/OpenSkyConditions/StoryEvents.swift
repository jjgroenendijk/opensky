// One builder per story-manager event that play fires. The member order follows
// the Creation Kit wiki event-data list of each event; docs/engine/story-manager.md
// has the table and the sources.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// Takes the events that gameplay coordinators raise. The app forwards them to the
/// story manager.
@MainActor
public protocol StoryEventReporting: AnyObject {
    func reportStoryEvent(_ event: StoryEventData)
}

/// The `V1` crime type of `ARRT` and `ADCR` (<https://ck.uesp.net/wiki/Arrest_Event>).
nonisolated public enum StoryCrimeType: Int, Sendable {
    case steal, pickpocket, trespass, assault, murder, escapeJail, werewolf
}

/// The `V1` crime status of `KILL` (<https://ck.uesp.net/wiki/Kill_Actor_Event>).
nonisolated public enum StoryKillStatus: Int, Sendable {
    case notMurder, murder, reportedMurder
}

/// The `V1` of `AIPL` (<https://ck.uesp.net/wiki/Player_Add_Item>).
nonisolated public enum StoryAcquireType: Int, Sendable {
    case none, steal, buy, pickpocket, pickUp, container, deadBody
}

/// The `V1` of `REMP` (<https://ck.uesp.net/wiki/Player_Remove_Item>).
nonisolated public enum StoryRemoveType: Int, Sendable {
    case none, stolen, consumed, script, dropped, given, putInContainer
}

nonisolated extension StoryEventData {
    public static func kill(
        killer: ReferenceKey?,
        victim: ReferenceKey,
        location: ResolvedFormID?,
        status: StoryKillStatus,
        rankBeforeDeath: Int8
    ) -> StoryEventData {
        var event = StoryEventData(event: "KILL")
        event.actor1 = killer
        event.actor2 = victim
        event.location1 = location
        event.value1 = Float(status.rawValue)
        event.value2 = Float(rankBeforeDeath)
        return event
    }

    /// `V1` holds the skill's actor-value index. No vanilla condition reads it.
    public static func skillIncrease(skill: Int32) -> StoryEventData {
        var event = StoryEventData(event: "SKIL")
        event.actor1 = .player
        event.value1 = Float(skill)
        return event
    }

    public static func levelIncrease(level: Int) -> StoryEventData {
        var event = StoryEventData(event: "LEVL")
        event.actor1 = .player
        event.value1 = Float(level)
        return event
    }

    public static func craft(
        actor: ReferenceKey,
        workbench: ReferenceKey?,
        location: ResolvedFormID?,
        created: FormID?
    ) -> StoryEventData {
        var event = StoryEventData(event: "CRFT")
        event.actor1 = actor
        event.actor2 = workbench
        event.location1 = location
        event.createdObject = created
        return event
    }

    public static func arrest(
        guardActor: ReferenceKey,
        criminal: ReferenceKey,
        location: ResolvedFormID?,
        crime: StoryCrimeType
    ) -> StoryEventData {
        var event = StoryEventData(event: "ARRT")
        event.actor1 = guardActor
        event.actor2 = criminal
        event.location1 = location
        event.value1 = Float(crime.rawValue)
        return event
    }

    public static func jail(
        location: ResolvedFormID?,
        guardActor: ReferenceKey?,
        crimeFaction: ReferenceKey,
        gold: Int32
    ) -> StoryEventData {
        var event = StoryEventData(event: "JAIL")
        event.location1 = location
        event.actor1 = guardActor
        event.form = form(of: crimeFaction)
        event.value1 = Float(gold)
        return event
    }

    public static func crimeGold(
        criminal: ReferenceKey,
        victim: ReferenceKey?,
        crimeFaction: ReferenceKey,
        gold: Int32,
        crime: StoryCrimeType
    ) -> StoryEventData {
        var event = StoryEventData(event: "ADCR")
        event.actor1 = criminal
        event.actor2 = victim
        event.form = form(of: crimeFaction)
        event.value1 = Float(gold)
        event.value2 = Float(crime.rawValue)
        return event
    }

    public static func assault(
        attacker: ReferenceKey,
        victim: ReferenceKey,
        location: ResolvedFormID?
    ) -> StoryEventData {
        var event = StoryEventData(event: "ASSU")
        event.actor1 = attacker
        event.actor2 = victim
        event.location1 = location
        return event
    }

    public static func lockPick(actor: ReferenceKey, lock: ReferenceKey) -> StoryEventData {
        var event = StoryEventData(event: "LOCK")
        event.actor1 = actor
        event.actor2 = lock
        return event
    }

    /// `F1` is the spell. The wiki lists only the caster and target; the vanilla
    /// `CAST` nodes test `F1` and fill aliases from `L1`.
    public static func castMagic(
        caster: ReferenceKey,
        target: ReferenceKey?,
        location: ResolvedFormID?,
        spell: FormID?
    ) -> StoryEventData {
        var event = StoryEventData(event: "CAST")
        event.actor1 = caster
        event.actor2 = target
        event.location1 = location
        event.form = spell
        return event
    }

    public static func relationshipRank(
        _ actor1: ReferenceKey,
        _ actor2: ReferenceKey,
        old: Int8,
        new: Int8
    ) -> StoryEventData {
        var event = StoryEventData(event: "CHRR")
        event.actor1 = actor1
        event.actor2 = actor2
        event.value1 = Float(old)
        event.value2 = Float(new)
        return event
    }

    public static func addItem(
        _ item: FormID,
        from container: ReferenceKey?,
        owner: ReferenceKey?,
        how: StoryAcquireType
    ) -> StoryEventData {
        var event = StoryEventData(event: "AIPL")
        event.actor1 = container
        event.actor2 = owner
        event.form = item
        event.value1 = Float(how.rawValue)
        return event
    }

    public static func removeItem(
        _ item: FormID,
        reference: ReferenceKey?,
        owner: ReferenceKey?,
        how: StoryRemoveType
    ) -> StoryEventData {
        var event = StoryEventData(event: "REMP")
        event.actor1 = reference
        event.actor2 = owner
        event.form = item
        event.value1 = Float(how.rawValue)
        return event
    }

    /// A key as the FormID number conditions compare, in `Skyrim.esm` numbering.
    public static func form(of key: ReferenceKey) -> FormID? {
        guard case let .plugin(_, objectID) = key else { return nil }
        return FormID(objectID)
    }
}
