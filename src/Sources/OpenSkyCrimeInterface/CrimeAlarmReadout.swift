// What `state alarm` shows of the session's alarms. See docs/engine/crime-reports.md#the-alarm.

public import OpenSkyFormatsESM

/// The alarms now: who runs an Alarm package and why, who fights whom, and the theft mark.
nonisolated public struct CrimeAlarmReadout: Sendable {
    nonisolated public struct Witness: Equatable, Sendable {
        public let key: ReferenceKey
        /// `pursue`, `fight`, `done`, `flee`, or `takeBack`.
        public let role: String
        public let criminal: ReferenceKey?
        public let crimes: Int

        public init(key: ReferenceKey, role: String, criminal: ReferenceKey?, crimes: Int) {
            self.key = key
            self.role = role
            self.criminal = criminal
            self.crimes = crimes
        }
    }

    /// One witness and the criminals it fights.
    nonisolated public struct Fighter: Equatable, Sendable {
        public let witness: ReferenceKey
        public let criminals: [ReferenceKey]

        public init(witness: ReferenceKey, criminals: [ReferenceKey]) {
            self.witness = witness
            self.criminals = criminals
        }
    }

    public let witnesses: [Witness]
    public let fighters: [Fighter]
    public let angry: [ReferenceKey]
    /// The game day the player's theft mark was set, or nil.
    public let theftMarkDay: Int?
    public let openCrimes: Int
    public let last: String
    /// The player's jail stay, from the arrest to release or escape.
    public let jail: JailStay?
    /// Followers waiting at the jail door.
    public let jailFollowers: [ReferenceKey]
    /// The player's trespass state in the cell they stand in.
    public var trespass = Trespass()

    /// See docs/engine/crime.md#who-may-be-in-a-private-cell.
    nonisolated public struct Trespass: Equatable, Sendable {
        public var isTrespassing = false
        public var isWarnedToLeave = false
        /// The owner opened the cell through its doors, or a script made it public.
        public var isCellOpened = false

        public init(
            isTrespassing: Bool = false,
            isWarnedToLeave: Bool = false,
            isCellOpened: Bool = false
        ) {
            self.isTrespassing = isTrespassing
            self.isWarnedToLeave = isWarnedToLeave
            self.isCellOpened = isCellOpened
        }
    }

    public init(
        witnesses: [Witness] = [],
        fighters: [Fighter] = [],
        angry: [ReferenceKey] = [],
        theftMarkDay: Int? = nil,
        openCrimes: Int = 0,
        last: String = "none",
        jail: JailStay? = nil,
        jailFollowers: [ReferenceKey] = []
    ) {
        self.jail = jail
        self.jailFollowers = jailFollowers
        self.witnesses = witnesses
        self.fighters = fighters
        self.angry = angry
        self.theftMarkDay = theftMarkDay
        self.openCrimes = openCrimes
        self.last = last
    }
}
