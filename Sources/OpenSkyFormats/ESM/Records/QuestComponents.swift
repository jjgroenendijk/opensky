// The four grouped structures inside a QUST record: stages with their journal
// log entries, objectives with their targets, and alias definitions. See
// Quest.swift for the record's ordering rules and its reference block; the
// grouping state machine that fills these lives in QuestDecoder.swift.

import Foundation

nonisolated extension Quest {
    /// One INDX group. A quest advances by stage index, and the same index may
    /// legally appear more than once in a record.
    public struct Stage: Equatable, Sendable {
        public struct Flags: OptionSet, Equatable, Sendable {
            public let rawValue: UInt8

            public init(rawValue: UInt8) {
                self.rawValue = rawValue
            }

            /// Setting this stage starts the quest.
            public static let startUpStage = Flags(rawValue: 1 << 1)
            /// Setting this stage stops the quest.
            public static let shutDownStage = Flags(rawValue: 1 << 2)
            public static let keepInstanceDataFromHereOn = Flags(rawValue: 1 << 3)
        }

        /// INDX word 0. uint16 per xEdit, and never negative in vanilla data.
        public var index: UInt16 = 0
        public var flags = Flags()
        /// QSDT groups under this stage, in file order. More than one means
        /// the journal picks between them by condition.
        public var logEntries: [LogEntry] = []

        /// The first log entry whose conditions the journal would evaluate.
        /// Choosing between several is the runtime's job (#182), not the
        /// decoder's; this is only the file-order default.
        public var primaryLogEntry: LogEntry? {
            logEntries.first { $0.text != nil } ?? logEntries.first
        }
    }

    /// One QSDT group inside a stage: the journal text shown when the stage is
    /// set, plus the conditions that select it and the quest-ending flags.
    public struct LogEntry: Equatable, Sendable {
        public struct Flags: OptionSet, Equatable, Sendable {
            public let rawValue: UInt8

            public init(rawValue: UInt8) {
                self.rawValue = rawValue
            }

            public static let completeQuest = Flags(rawValue: 1 << 0)
            public static let failQuest = Flags(rawValue: 1 << 1)
        }

        public var flags = Flags()
        public var conditions = ConditionList()
        /// CNAM, the journal paragraph. Localized plugins hold a string ID.
        public var text: LString?
        /// NAM0, a QUST this entry hands off to.
        public var nextQuest: FormID?
    }

    /// One QOBJ group: an objective line in the journal and the map targets
    /// it points at.
    public struct Objective: Equatable, Sendable {
        public struct Flags: OptionSet, Equatable, Sendable {
            public let rawValue: UInt32

            public init(rawValue: UInt32) {
                self.rawValue = rawValue
            }

            /// This objective is satisfied by itself or the previous one.
            public static let oredWithPrevious = Flags(rawValue: 1 << 0)
        }

        /// QOBJ. By convention it matches a stage index, but nothing enforces
        /// that, and duplicates are legal.
        public var index: UInt16 = 0
        public var flags = Flags()
        /// NNAM, the objective text. Required by xEdit; absent only in
        /// malformed data.
        public var displayText: LString?
        public var targets: [Target] = []
    }

    /// One QSTA group: which alias the compass marker points at.
    ///
    ///   0  int32  alias ID, or a direct reference FormID for the record-level
    ///             legacy target array
    ///   4  uint8  compass marker ignores locks
    ///   5  3      unused
    public struct Target: Equatable, Sendable {
        /// The QSTA word. Read as the alias ID for an objective target and as
        /// a reference FormID for a record-level legacy target, which is why
        /// it is kept as the raw signed word plus the two typed accessors.
        public var rawTarget: Int32 = 0
        public var compassMarkerIgnoresLocks = false
        public var conditions = ConditionList()

        /// Alias ID this target follows, for an objective target.
        public var aliasID: Int32 {
            rawTarget
        }

        /// Reference this target points at, for a legacy record-level target.
        public var reference: FormID {
            FormID(UInt32(bitPattern: rawTarget))
        }
    }

    /// One ALST (reference) or ALLS (location) group.
    ///
    /// The Creation Kit presents an alias as having exactly one "fill type",
    /// but on disk that choice is implied by which of a dozen mutually
    /// exclusive subrecords appear. Rather than guess the intent while
    /// parsing, every slot is decoded into its own property and `fillType`
    /// reports the choice afterwards. That keeps a mod that writes an
    /// unexpected combination readable instead of throwing, and it gives the
    /// census a fill-type axis without a second pass over the bytes.
    public struct Alias: Equatable, Sendable {
        /// Which subrecord opened the group. Location aliases resolve to an
        /// LCTN, reference aliases to a placed ACHR or REFR.
        public enum Category: Equatable, Sendable {
            case reference
            case location
        }

        public struct Flags: OptionSet, Equatable, Sendable {
            public let rawValue: UInt32

            public init(rawValue: UInt32) {
                self.rawValue = rawValue
            }

            /// Loc/Ref. Reserves the location or reference for this quest.
            public static let reserves = Flags(rawValue: 1 << 0)
            public static let optional = Flags(rawValue: 1 << 1)
            /// Ref. The alias target is a quest object, undroppable while the
            /// quest runs.
            public static let questObject = Flags(rawValue: 1 << 2)
            public static let allowReuseInQuest = Flags(rawValue: 1 << 3)
            public static let allowDead = Flags(rawValue: 1 << 4)
            public static let matchingRefInLoadedArea = Flags(rawValue: 1 << 5)
            /// Ref. Makes the target essential while the quest runs.
            public static let essential = Flags(rawValue: 1 << 6)
            public static let allowDisabled = Flags(rawValue: 1 << 7)
            public static let storesText = Flags(rawValue: 1 << 8)
            public static let allowReserved = Flags(rawValue: 1 << 9)
            public static let protected = Flags(rawValue: 1 << 10)
            public static let forcedByAliases = Flags(rawValue: 1 << 11)
            public static let allowDestroyed = Flags(rawValue: 1 << 12)
            public static let matchingRefClosest = Flags(rawValue: 1 << 13)
            public static let usesStoredText = Flags(rawValue: 1 << 14)
            public static let initiallyDisabled = Flags(rawValue: 1 << 15)
            /// Loc only; the same bit is unnamed for reference aliases.
            public static let allowCleared = Flags(rawValue: 1 << 16)
            public static let clearsNameWhenRemoved = Flags(rawValue: 1 << 17)
        }

        /// How the alias gets its value, derived from which slots were filled.
        /// The order matches the Creation Kit's own union order, so an alias
        /// that somehow carries two fill subrecords reports the one the editor
        /// would have shown.
        public enum FillType: Equatable, Sendable {
            /// Ref: ALFR names a specific placed reference.
            case specificReference
            /// Ref: ALUA names an NPC whose unique instance fills the alias.
            case uniqueActor
            /// Ref: ALFA + ALRT — a location alias plus an LCRT ref type.
            case locationAliasReference
            /// Loc: ALFL names a specific LCTN.
            case specificLocation
            /// Loc: ALFA + KNAM — a reference alias plus a keyword.
            case referenceAliasLocation
            /// Loc/Ref: ALEQ + ALEA copy an alias from another quest.
            case externalAlias
            /// Ref: ALCO creates a new instance of a base object.
            case createReferenceToObject
            /// Ref: ALNA + ALNT match a reference near another alias.
            case nearAlias
            /// Loc/Ref: ALFE + ALFD fill from a story-manager event.
            case fromEvent
            /// No fill subrecord: filled by script, forced in from another
            /// alias (ALFI), or matched purely on conditions.
            case none

            public var name: String {
                switch self {
                case .specificReference: "specific reference"
                case .uniqueActor: "unique actor"
                case .locationAliasReference: "location alias reference"
                case .specificLocation: "specific location"
                case .referenceAliasLocation: "reference alias location"
                case .externalAlias: "external alias"
                case .createReferenceToObject: "create reference to object"
                case .nearAlias: "near alias"
                case .fromEvent: "from event"
                case .none: "none"
                }
            }
        }

        /// One CNTO entry: an item added to the alias target for the quest.
        /// No COED follows these, unlike the container form.
        public struct Item: Equatable, Sendable {
            public let item: FormID
            public let count: Int32
        }

        /// ALST / ALLS. The number scripts and conditions address the alias by.
        public let id: UInt32
        public let category: Category
        /// ALID, the authoring name — "QuestGiver", "Location". Substituted
        /// into journal text through the <Alias=Name> markup.
        public var name: String?
        public var flags = Flags()
        /// ALFI, the alias this one is forced into when it fills.
        public var forceIntoAlias: Int32?

        // Fill-type slots, one per documented subrecord.
        public var forcedReference: FormID? // ALFR
        public var uniqueActor: FormID? // ALUA
        public var forcedLocation: FormID? // ALFL
        public var aliasReference: Int32? // ALFA
        public var referenceType: FormID? // ALRT
        public var keyword: FormID? // KNAM
        public var externalQuest: FormID? // ALEQ
        public var externalAlias: Int32? // ALEA
        public var createdObject: FormID? // ALCO
        /// ALCA: low 16 bits are the alias to create at, high bit 0x8000
        /// switches "create at" to "create in".
        public var createAt: UInt32?
        public var createLevel: UInt32? // ALCL
        public var nearAlias: Int32? // ALNA
        public var nearType: UInt32? // ALNT
        public var fromEvent: UInt32? // ALFE
        public var eventData: UInt32? // ALFD

        /// The CTDA run inside the alias — the "match conditions" the fill
        /// search uses, not conditions on the quest.
        public var matchConditions = ConditionList()
        /// KSIZ/KWDA: keywords added to the target for the quest's duration.
        public var keywords = KeywordList()
        /// COCT as written; advisory, exactly as on CONT.
        public var declaredItemCount: UInt32?
        /// CNTO: items given to the target for the quest's duration.
        public var items: [Item] = []
        public var spells: [FormID] = [] // ALSP
        public var factions: [FormID] = [] // ALFC
        public var packages: [FormID] = [] // ALPC
        public var displayName: FormID? // ALDN
        public var voiceTypes: FormID? // VTCK
        public var spectatorOverride: FormID? // SPOR
        public var observeDeadBodyOverride: FormID? // OCOR
        public var guardWarnOverride: FormID? // GWOR
        public var combatOverride: FormID? // ECOR

        public init(id: UInt32, category: Category) {
            self.id = id
            self.category = category
        }

        /// One branch per documented fill subrecord, in the Creation Kit's
        /// own union order.
        public var fillType: FillType {
            if forcedReference != nil {
                return .specificReference
            }
            if uniqueActor != nil {
                return .uniqueActor
            }
            if forcedLocation != nil {
                return .specificLocation
            }
            if aliasReference != nil, referenceType != nil {
                return .locationAliasReference
            }
            if aliasReference != nil, keyword != nil {
                return .referenceAliasLocation
            }
            if aliasReference != nil {
                // ALFA without its companion: the category still says which of
                // the two forms was meant.
                return category == .reference ? .locationAliasReference : .referenceAliasLocation
            }
            if externalQuest != nil {
                return .externalAlias
            }
            if createdObject != nil {
                return .createReferenceToObject
            }
            if nearAlias != nil {
                return .nearAlias
            }
            if fromEvent != nil {
                return .fromEvent
            }
            return .none
        }
    }
}
