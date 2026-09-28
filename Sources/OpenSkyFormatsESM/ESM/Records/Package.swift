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

nonisolated public struct Package: Equatable, Sendable {
    public struct GeneralFlags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let mustComplete = GeneralFlags(rawValue: 0x0000_0004)
        public static let maintainSpeedAtGoal = GeneralFlags(rawValue: 0x0000_0008)
        public static let oncePerDay = GeneralFlags(rawValue: 0x0000_0400)
        public static let usesPreferredSpeed = GeneralFlags(rawValue: 0x0000_2000)
        public static let alwaysSneak = GeneralFlags(rawValue: 0x0002_0000)
        public static let ignoreCombat = GeneralFlags(rawValue: 0x0010_0000)
        public static let weaponsUnequipped = GeneralFlags(rawValue: 0x0020_0000)
        public static let weaponDrawn = GeneralFlags(rawValue: 0x0080_0000)
        public static let wearSleepOutfit = GeneralFlags(rawValue: 0x2000_0000)
    }

    public enum Kind: Equatable, Sendable {
        case package
        case template
        case unknown(UInt8)

        public init(rawValue: UInt8) {
            switch rawValue {
            case 18: self = .package
            case 19: self = .template
            default: self = .unknown(rawValue)
            }
        }
    }

    public enum PreferredSpeed: Equatable, Sendable {
        case walk
        case jog
        case run
        case fastWalk
        case unknown(UInt8)

        public init(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .walk
            case 1: self = .jog
            case 2: self = .run
            case 3: self = .fastWalk
            default: self = .unknown(rawValue)
            }
        }
    }

    public struct GeneralData: Equatable, Sendable {
        public let flags: GeneralFlags
        public let kind: Kind
        public let interruptOverride: UInt8
        public let preferredSpeed: PreferredSpeed
        public let interruptFlags: UInt16
    }

    public struct Schedule: Equatable, Sendable {
        /// -1 means any; positive values are 1-based months.
        public let month: Int8
        /// -1 any, 0...6 individual weekdays, 7...10 grouped weekdays.
        public let dayOfWeek: Int8
        /// 0 means any; otherwise a 1-based day of month.
        public let date: Int8
        /// -1 means any; otherwise 0...23.
        public let hour: Int8
        /// -1 means the start of the authored hour; otherwise 0...59.
        public let minute: Int8
        public let durationMinutes: UInt32

        public static let anytime = Schedule(
            month: -1,
            dayOfWeek: -1,
            date: 0,
            hour: -1,
            minute: -1,
            durationMinutes: 0
        )
    }

    public enum LocationKind: Int32, Equatable, Sendable {
        case nearReference = 0
        case inCell = 1
        case nearPackageStart = 2
        case nearEditorLocation = 3
        case nearLinkedReference = 6
        case referenceAlias = 8
        case locationAlias = 9
        case nearSelf = 12
    }

    public struct Location: Equatable, Sendable {
        public let rawKind: Int32
        public let value: UInt32
        public let radius: Int32

        public var kind: LocationKind? {
            LocationKind(rawValue: rawKind)
        }

        public var formID: FormID? {
            switch kind {
            case .nearReference, .inCell, .nearLinkedReference:
                value == 0 ? nil : FormID(value)
            default: nil
            }
        }
    }

    public enum TargetKind: Int32, Equatable, Sendable {
        case specificReference = 0
        case objectID = 1
        case objectType = 2
        case linkedReference = 3
        case referenceAlias = 4
        case unknown = 5
        case actor = 6
    }

    public struct Target: Equatable, Sendable {
        public let rawKind: Int32
        public let value: UInt32
        public let countOrDistance: Int32

        public var kind: TargetKind? {
            TargetKind(rawValue: rawKind)
        }
    }

    public enum DataValue: Equatable, Sendable {
        case boolean(Bool)
        case integer(Int32)
        case float(Float)
        case location(Location)
        case target(Target)
        case topic(FormID)
        case unknown(type: String, bytes: Int)
    }

    public struct DataInput: Equatable, Sendable {
        public let index: Int8?
        public let type: String
        public let value: DataValue
    }

    public let formID: FormID
    public let editorID: String?
    public let general: GeneralData
    public let schedule: Schedule
    public let conditions: ConditionList
    public let template: FormID?
    public let dataInputs: [DataInput]
    /// Procedure names from template-package PNAM zstrings, in record order.
    public let procedureTypes: [String]
    public let scriptData: ScriptData
}

nonisolated extension Package {
    public init(record: ESMRecord) throws {
        self = try PackageDecoder.decode(record)
    }
}
