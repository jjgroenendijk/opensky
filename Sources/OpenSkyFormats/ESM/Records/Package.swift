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

nonisolated package struct Package: Equatable {
    package struct GeneralFlags: OptionSet, Equatable, Sendable {
        package let rawValue: UInt32

        package init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        package static let mustComplete = GeneralFlags(rawValue: 0x0000_0004)
        package static let maintainSpeedAtGoal = GeneralFlags(rawValue: 0x0000_0008)
        package static let oncePerDay = GeneralFlags(rawValue: 0x0000_0400)
        package static let usesPreferredSpeed = GeneralFlags(rawValue: 0x0000_2000)
        package static let alwaysSneak = GeneralFlags(rawValue: 0x0002_0000)
        package static let ignoreCombat = GeneralFlags(rawValue: 0x0010_0000)
        package static let weaponsUnequipped = GeneralFlags(rawValue: 0x0020_0000)
        package static let weaponDrawn = GeneralFlags(rawValue: 0x0080_0000)
        package static let wearSleepOutfit = GeneralFlags(rawValue: 0x2000_0000)
    }

    package enum Kind: Equatable, Sendable {
        case package
        case template
        case unknown(UInt8)

        package init(rawValue: UInt8) {
            switch rawValue {
            case 18: self = .package
            case 19: self = .template
            default: self = .unknown(rawValue)
            }
        }
    }

    package enum PreferredSpeed: Equatable, Sendable {
        case walk
        case jog
        case run
        case fastWalk
        case unknown(UInt8)

        package init(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .walk
            case 1: self = .jog
            case 2: self = .run
            case 3: self = .fastWalk
            default: self = .unknown(rawValue)
            }
        }
    }

    package struct GeneralData: Equatable, Sendable {
        package let flags: GeneralFlags
        package let kind: Kind
        package let interruptOverride: UInt8
        package let preferredSpeed: PreferredSpeed
        package let interruptFlags: UInt16
    }

    package struct Schedule: Equatable, Sendable {
        /// -1 means any; positive values are 1-based months.
        package let month: Int8
        /// -1 any, 0...6 individual weekdays, 7...10 grouped weekdays.
        package let dayOfWeek: Int8
        /// 0 means any; otherwise a 1-based day of month.
        package let date: Int8
        /// -1 means any; otherwise 0...23.
        package let hour: Int8
        /// -1 means the start of the authored hour; otherwise 0...59.
        package let minute: Int8
        package let durationMinutes: UInt32

        package static let anytime = Schedule(
            month: -1,
            dayOfWeek: -1,
            date: 0,
            hour: -1,
            minute: -1,
            durationMinutes: 0
        )
    }

    package enum LocationKind: Int32, Equatable, Sendable {
        case nearReference = 0
        case inCell = 1
        case nearPackageStart = 2
        case nearEditorLocation = 3
        case nearLinkedReference = 6
        case referenceAlias = 8
        case locationAlias = 9
        case nearSelf = 12
    }

    package struct Location: Equatable, Sendable {
        package let rawKind: Int32
        package let value: UInt32
        package let radius: Int32

        package var kind: LocationKind? {
            LocationKind(rawValue: rawKind)
        }

        package var formID: FormID? {
            switch kind {
            case .nearReference, .inCell, .nearLinkedReference:
                value == 0 ? nil : FormID(value)
            default: nil
            }
        }
    }

    package enum TargetKind: Int32, Equatable, Sendable {
        case specificReference = 0
        case objectID = 1
        case objectType = 2
        case linkedReference = 3
        case referenceAlias = 4
        case unknown = 5
        case actor = 6
    }

    package struct Target: Equatable, Sendable {
        package let rawKind: Int32
        package let value: UInt32
        package let countOrDistance: Int32

        package var kind: TargetKind? {
            TargetKind(rawValue: rawKind)
        }
    }

    package enum DataValue: Equatable, Sendable {
        case boolean(Bool)
        case integer(Int32)
        case float(Float)
        case location(Location)
        case target(Target)
        case topic(FormID)
        case unknown(type: String, bytes: Int)
    }

    package struct DataInput: Equatable, Sendable {
        package let index: Int8?
        package let type: String
        package let value: DataValue
    }

    package let formID: FormID
    package let editorID: String?
    package let general: GeneralData
    package let schedule: Schedule
    package let conditions: ConditionList
    package let template: FormID?
    package let dataInputs: [DataInput]
    /// Procedure names from template-package PNAM zstrings, in record order.
    package let procedureTypes: [String]
    package let scriptData: ScriptData
}

nonisolated extension Package {
    package init(record: ESMRecord) throws {
        self = try PackageDecoder.decode(record)
    }
}
