// The four grouped structures inside a QUST record: stages with their journal
// log entries, objectives with their targets, and alias definitions. See
// Quest.swift for the record's ordering rules and its reference block; the
// grouping state machine that fills these lives in QuestDecoder.swift.

import Foundation

nonisolated extension Quest {
    /// One INDX group. A quest advances by stage index, and the same index may
    /// legally appear more than once in a record.
    struct Stage: Equatable {
        struct Flags: OptionSet, Equatable {
            let rawValue: UInt8

            /// Setting this stage starts the quest.
            static let startUpStage = Flags(rawValue: 1 << 1)
            /// Setting this stage stops the quest.
            static let shutDownStage = Flags(rawValue: 1 << 2)
            static let keepInstanceDataFromHereOn = Flags(rawValue: 1 << 3)
        }

        /// INDX word 0. uint16 per xEdit, and never negative in vanilla data.
        var index: UInt16 = 0
        var flags = Flags()
        /// QSDT groups under this stage, in file order. More than one means
        /// the journal picks between them by condition.
        var logEntries: [LogEntry] = []

        /// The first log entry whose conditions the journal would evaluate.
        /// Choosing between several is the runtime's job (#182), not the
        /// decoder's; this is only the file-order default.
        var primaryLogEntry: LogEntry? {
            logEntries.first { $0.text != nil } ?? logEntries.first
        }
    }

    /// One QSDT group inside a stage: the journal text shown when the stage is
    /// set, plus the conditions that select it and the quest-ending flags.
    struct LogEntry: Equatable {
        struct Flags: OptionSet, Equatable {
            let rawValue: UInt8

            static let completeQuest = Flags(rawValue: 1 << 0)
            static let failQuest = Flags(rawValue: 1 << 1)
        }

        var flags = Flags()
        var conditions = ConditionList()
        /// CNAM, the journal paragraph. Localized plugins hold a string ID.
        var text: LString?
        /// NAM0, a QUST this entry hands off to.
        var nextQuest: FormID?
    }

    /// One QOBJ group: an objective line in the journal and the map targets
    /// it points at.
    struct Objective: Equatable {
        struct Flags: OptionSet, Equatable {
            let rawValue: UInt32

            /// This objective is satisfied by itself or the previous one.
            static let oredWithPrevious = Flags(rawValue: 1 << 0)
        }

        /// QOBJ. By convention it matches a stage index, but nothing enforces
        /// that, and duplicates are legal.
        var index: UInt16 = 0
        var flags = Flags()
        /// NNAM, the objective text. Required by xEdit; absent only in
        /// malformed data.
        var displayText: LString?
        var targets: [Target] = []
    }

    /// One QSTA group: which alias the compass marker points at.
    ///
    ///   0  int32  alias ID, or a direct reference FormID for the record-level
    ///             legacy target array
    ///   4  uint8  compass marker ignores locks
    ///   5  3      unused
    struct Target: Equatable {
        /// The QSTA word. Read as the alias ID for an objective target and as
        /// a reference FormID for a record-level legacy target, which is why
        /// it is kept as the raw signed word plus the two typed accessors.
        var rawTarget: Int32 = 0
        var compassMarkerIgnoresLocks = false
        var conditions = ConditionList()

        /// Alias ID this target follows, for an objective target.
        var aliasID: Int32 {
            rawTarget
        }

        /// Reference this target points at, for a legacy record-level target.
        var reference: FormID {
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
    struct Alias: Equatable {
        /// Which subrecord opened the group. Location aliases resolve to an
        /// LCTN, reference aliases to a placed ACHR or REFR.
        enum Category: Equatable {
            case reference
            case location
        }

        struct Flags: OptionSet, Equatable {
            let rawValue: UInt32

            /// Loc/Ref. Reserves the location or reference for this quest.
            static let reserves = Flags(rawValue: 1 << 0)
            static let optional = Flags(rawValue: 1 << 1)
            /// Ref. The alias target is a quest object, undroppable while the
            /// quest runs.
            static let questObject = Flags(rawValue: 1 << 2)
            static let allowReuseInQuest = Flags(rawValue: 1 << 3)
            static let allowDead = Flags(rawValue: 1 << 4)
            static let matchingRefInLoadedArea = Flags(rawValue: 1 << 5)
            /// Ref. Makes the target essential while the quest runs.
            static let essential = Flags(rawValue: 1 << 6)
            static let allowDisabled = Flags(rawValue: 1 << 7)
            static let storesText = Flags(rawValue: 1 << 8)
            static let allowReserved = Flags(rawValue: 1 << 9)
            static let protected = Flags(rawValue: 1 << 10)
            static let forcedByAliases = Flags(rawValue: 1 << 11)
            static let allowDestroyed = Flags(rawValue: 1 << 12)
            static let matchingRefClosest = Flags(rawValue: 1 << 13)
            static let usesStoredText = Flags(rawValue: 1 << 14)
            static let initiallyDisabled = Flags(rawValue: 1 << 15)
            /// Loc only; the same bit is unnamed for reference aliases.
            static let allowCleared = Flags(rawValue: 1 << 16)
            static let clearsNameWhenRemoved = Flags(rawValue: 1 << 17)
        }

        /// How the alias gets its value, derived from which slots were filled.
        /// The order matches the Creation Kit's own union order, so an alias
        /// that somehow carries two fill subrecords reports the one the editor
        /// would have shown.
        enum FillType: Equatable {
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

            var name: String {
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
        struct Item: Equatable {
            let item: FormID
            let count: Int32
        }

        /// ALST / ALLS. The number scripts and conditions address the alias by.
        let id: UInt32
        let category: Category
        /// ALID, the authoring name — "QuestGiver", "Location". Substituted
        /// into journal text through the <Alias=Name> markup.
        var name: String?
        var flags = Flags()
        /// ALFI, the alias this one is forced into when it fills.
        var forceIntoAlias: Int32?

        // Fill-type slots, one per documented subrecord.
        var forcedReference: FormID? // ALFR
        var uniqueActor: FormID? // ALUA
        var forcedLocation: FormID? // ALFL
        var aliasReference: Int32? // ALFA
        var referenceType: FormID? // ALRT
        var keyword: FormID? // KNAM
        var externalQuest: FormID? // ALEQ
        var externalAlias: Int32? // ALEA
        var createdObject: FormID? // ALCO
        /// ALCA: low 16 bits are the alias to create at, high bit 0x8000
        /// switches "create at" to "create in".
        var createAt: UInt32?
        var createLevel: UInt32? // ALCL
        var nearAlias: Int32? // ALNA
        var nearType: UInt32? // ALNT
        var fromEvent: UInt32? // ALFE
        var eventData: UInt32? // ALFD

        /// The CTDA run inside the alias — the "match conditions" the fill
        /// search uses, not conditions on the quest.
        var matchConditions = ConditionList()
        /// KSIZ/KWDA: keywords added to the target for the quest's duration.
        var keywords = KeywordList()
        /// COCT as written; advisory, exactly as on CONT.
        var declaredItemCount: UInt32?
        /// CNTO: items given to the target for the quest's duration.
        var items: [Item] = []
        var spells: [FormID] = [] // ALSP
        var factions: [FormID] = [] // ALFC
        var packages: [FormID] = [] // ALPC
        var displayName: FormID? // ALDN
        var voiceTypes: FormID? // VTCK
        var spectatorOverride: FormID? // SPOR
        var observeDeadBodyOverride: FormID? // OCOR
        var guardWarnOverride: FormID? // GWOR
        var combatOverride: FormID? // ECOR

        init(id: UInt32, category: Category) {
            self.id = id
            self.category = category
        }

        /// One branch per documented fill subrecord, in the Creation Kit's
        /// own union order.
        var fillType: FillType {
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
