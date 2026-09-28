// PACK record values used by AI schedule selection and the first bounded
// procedure runtime (issue #201).
//
// References:
// - UESP "Skyrim Mod:Mod File Format/PACK"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PACK
// - xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbRecord(PACK)`
//   https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
//
// The complete bounded layout and deliberately skipped fields are recorded in
// docs/formats/packages.md. Unknown enum values remain raw instead of failing;
// malformed fixed-width values throw through BinaryReader.

import Foundation

nonisolated struct Package: Equatable {
    struct GeneralFlags: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        static let mustComplete = GeneralFlags(rawValue: 0x0000_0004)
        static let maintainSpeedAtGoal = GeneralFlags(rawValue: 0x0000_0008)
        static let oncePerDay = GeneralFlags(rawValue: 0x0000_0400)
        static let usesPreferredSpeed = GeneralFlags(rawValue: 0x0000_2000)
        static let alwaysSneak = GeneralFlags(rawValue: 0x0002_0000)
        static let ignoreCombat = GeneralFlags(rawValue: 0x0010_0000)
        static let weaponsUnequipped = GeneralFlags(rawValue: 0x0020_0000)
        static let weaponDrawn = GeneralFlags(rawValue: 0x0080_0000)
        static let wearSleepOutfit = GeneralFlags(rawValue: 0x2000_0000)
    }

    enum Kind: Equatable, Sendable {
        case package
        case template
        case unknown(UInt8)

        init(rawValue: UInt8) {
            switch rawValue {
            case 18: self = .package
            case 19: self = .template
            default: self = .unknown(rawValue)
            }
        }
    }

    enum PreferredSpeed: Equatable, Sendable {
        case walk
        case jog
        case run
        case fastWalk
        case unknown(UInt8)

        init(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .walk
            case 1: self = .jog
            case 2: self = .run
            case 3: self = .fastWalk
            default: self = .unknown(rawValue)
            }
        }
    }

    struct GeneralData: Equatable, Sendable {
        let flags: GeneralFlags
        let kind: Kind
        let interruptOverride: UInt8
        let preferredSpeed: PreferredSpeed
        let interruptFlags: UInt16
    }

    struct Schedule: Equatable, Sendable {
        /// -1 means any; positive values are 1-based months.
        let month: Int8
        /// -1 any, 0...6 individual weekdays, 7...10 grouped weekdays.
        let dayOfWeek: Int8
        /// 0 means any; otherwise a 1-based day of month.
        let date: Int8
        /// -1 means any; otherwise 0...23.
        let hour: Int8
        /// -1 means the start of the authored hour; otherwise 0...59.
        let minute: Int8
        let durationMinutes: UInt32

        static let anytime = Schedule(
            month: -1,
            dayOfWeek: -1,
            date: 0,
            hour: -1,
            minute: -1,
            durationMinutes: 0
        )

        func matches(_ clock: GameClock) -> Bool {
            guard hour >= 0 else { return matchesCalendar(clock) }
            let start = Int(hour) * 60 + max(Int(minute), 0)
            let duration = Int(durationMinutes)
            let currentMinute = clockMinute(clock)
            guard duration > 0 else {
                return currentMinute == start && matchesCalendar(clock)
            }
            let elapsed = (currentMinute - start + Self.minutesPerDay)
                % Self.minutesPerDay
            guard duration >= Self.minutesPerDay || elapsed < duration else { return false }
            let wrapsFromPreviousDay = currentMinute < start
                && start + duration > Self.minutesPerDay
            let calendarClock = wrapsFromPreviousDay
                ? GameClock(totalGameSeconds: clock.totalGameSeconds - GameClock.secondsPerDay)
                : clock
            return matchesCalendar(calendarClock)
        }

        /// Next daily start/end edge, bounded to one day. Calendar-only edges
        /// are covered by the runtime's interval reevaluation.
        func minutesUntilBoundary(after clock: GameClock) -> Float? {
            guard hour >= 0 else { return nil }
            let now = clock.hourOfDay * 60
            let start = Float(Int(hour) * 60 + max(Int(minute), 0))
            var candidates = [Self.forwardMinutes(from: now, to: start)]
            if durationMinutes > 0, durationMinutes < UInt32(Self.minutesPerDay) {
                let end = Float((Int(start) + Int(durationMinutes)) % Self.minutesPerDay)
                candidates.append(Self.forwardMinutes(from: now, to: end))
            }
            return candidates.filter { $0 > 0 }.min()
        }

        private func matchesCalendar(_ clock: GameClock) -> Bool {
            let monthMatches = month < 0 || Int(month) == clock.month
            let dateMatches = date == 0 || Int(date) == clock.day
            return monthMatches && dateMatches && matchesWeekday(clock.packageWeekday)
        }

        private func matchesWeekday(_ weekday: Int) -> Bool {
            switch dayOfWeek {
            case -1: true
            case 0 ... 6: Int(dayOfWeek) == weekday
            case 7: (1 ... 5).contains(weekday)
            case 8: weekday == 0 || weekday == 6
            case 9: weekday == 1 || weekday == 3 || weekday == 5
            case 10: weekday == 2 || weekday == 4
            default: false
            }
        }

        private func clockMinute(_ clock: GameClock) -> Int {
            Int(clock.hourOfDay * 60) % Self.minutesPerDay
        }

        private static func forwardMinutes(from current: Float, to boundary: Float) -> Float {
            let delta = (boundary - current).truncatingRemainder(dividingBy: Float(minutesPerDay))
            return delta > 0 ? delta : delta + Float(minutesPerDay)
        }

        private static let minutesPerDay = 24 * 60
    }

    enum LocationKind: Int32, Equatable, Sendable {
        case nearReference = 0
        case inCell = 1
        case nearPackageStart = 2
        case nearEditorLocation = 3
        case nearLinkedReference = 6
        case referenceAlias = 8
        case locationAlias = 9
        case nearSelf = 12
    }

    struct Location: Equatable, Sendable {
        let rawKind: Int32
        let value: UInt32
        let radius: Int32

        var kind: LocationKind? {
            LocationKind(rawValue: rawKind)
        }

        var formID: FormID? {
            switch kind {
            case .nearReference, .inCell, .nearLinkedReference:
                value == 0 ? nil : FormID(value)
            default: nil
            }
        }
    }

    enum TargetKind: Int32, Equatable, Sendable {
        case specificReference = 0
        case objectID = 1
        case objectType = 2
        case linkedReference = 3
        case referenceAlias = 4
        case unknown = 5
        case actor = 6
    }

    struct Target: Equatable, Sendable {
        let rawKind: Int32
        let value: UInt32
        let countOrDistance: Int32

        var kind: TargetKind? {
            TargetKind(rawValue: rawKind)
        }
    }

    enum DataValue: Equatable, Sendable {
        case boolean(Bool)
        case integer(Int32)
        case float(Float)
        case location(Location)
        case target(Target)
        case topic(FormID)
        case unknown(type: String, bytes: Int)
    }

    struct DataInput: Equatable, Sendable {
        let index: Int8?
        let type: String
        let value: DataValue
    }

    let formID: FormID
    let editorID: String?
    let general: GeneralData
    let schedule: Schedule
    let conditions: ConditionList
    let template: FormID?
    let dataInputs: [DataInput]
    /// Procedure names from template-package PNAM zstrings, in record order.
    let procedureTypes: [String]
    let scriptData: ScriptData
}

nonisolated extension Package {
    init(record: ESMRecord) throws {
        self = try PackageDecoder.decode(record)
    }
}

nonisolated extension GameClock {
    /// PACK PSDT weekday index: Sundas = 0 ... Loredas = 6. Skyrim normally
    /// begins on Sundas, 17th of Last Seed, 4E 201 (UESP Skyrim:Calendar).
    var packageWeekday: Int {
        let days = Int(floor(Double(daysPassed)))
        return ((days % 7) + 7) % 7
    }
}
