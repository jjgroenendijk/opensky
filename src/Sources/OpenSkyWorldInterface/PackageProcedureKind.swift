// The AI procedures a package tree can name, by their `PNAM` names. The parameter
// lists are on the Creation Kit wiki procedure pages; docs/engine/package-schedules.md.

import Foundation

nonisolated public enum PackageProcedureKind: Hashable, Sendable {
    case travel
    /// Walks a chain of linked references from a start marker.
    case patrol
    case wander
    case sandbox
    case sleep
    case eat
    /// Walks to the furniture the package names and uses it.
    case sit
    /// Stays where it is and moves nowhere, as a rider in a cart does.
    case wait
    case acquire
    case activate
    case dialogueActivate
    case escort
    /// Searches a place for objects and fills an object list. It moves nobody.
    case find
    case flee
    case flightGrab
    case follow
    case followTo
    case forceGreet
    case guardArea
    case holdPosition
    case hover
    case keepAnEyeOn
    case lockDoors
    case unlockDoors
    case orbit
    case say
    case shout
    case useIdleMarker
    case useMagic
    case useWeapon
    case unsupported(String)

    /// Each `PNAM` name, lowercased, and its kind.
    private static let named: [(String, PackageProcedureKind)] = [
        ("travel", .travel), ("patrol", .patrol), ("wander", .wander),
        ("sandbox", .sandbox), ("sleep", .sleep), ("eat", .eat), ("sit", .sit),
        ("wait", .wait), ("acquire", .acquire), ("activate", .activate),
        ("dialogueactivate", .dialogueActivate), ("escort", .escort), ("find", .find),
        ("flee", .flee), ("flightgrab", .flightGrab), ("follow", .follow),
        ("followto", .followTo), ("forcegreet", .forceGreet), ("guard", .guardArea),
        ("holdposition", .holdPosition), ("hover", .hover), ("keepaneyeon", .keepAnEyeOn),
        ("lockdoors", .lockDoors), ("unlockdoors", .unlockDoors), ("orbit", .orbit),
        ("say", .say), ("shout", .shout), ("useidlemarker", .useIdleMarker),
        ("usemagic", .useMagic), ("useweapon", .useWeapon)
    ]

    private static let byName = Dictionary(uniqueKeysWithValues: named)

    /// Procedure names, lowercased, that an actor runs.
    public static let runnableNames = Set(named.map(\.0))

    public init(name: String) {
        self = Self.byName[name.lowercased()] ?? .unsupported(name)
    }

    /// The lowercased `PNAM` name, or the name an unsupported procedure carries.
    public var name: String {
        if case let .unsupported(name) = self {
            return name
        }
        return Self.named.first { $0.1 == self }?.0 ?? ""
    }
}
