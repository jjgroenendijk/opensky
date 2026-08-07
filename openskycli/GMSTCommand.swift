// `gmst movement` and `gmst combat`: read-only resolution reports for
// controller tuning and for melee combat (issue #195). Source names make both
// winning plugin overrides and explicit fallbacks inspectable, which is how a
// surprising reach or block number is traced to the plugin that set it rather
// than guessed at.

import Foundation

enum GMSTCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let subject = try scanner.positional("subject")
        try scanner.finish()
        switch subject {
        case "movement":
            try runMovement(context: context)
        case "combat":
            try runCombat(context: context)
        case "archery":
            try runArchery(context: context)
        default:
            throw CLIError.usage("unknown gmst subject: \(subject)")
        }
    }

    /// The eight settings `CombatSettings` resolves, with the plugin or the
    /// documented fallback each came from.
    private static func runCombat(context: CLIContext) throws {
        let file = try context.loadSkyrimESM()
        let store = GameSettingLoader.load(root: context.root, baseFile: file)
        for row in CombatSettings.resolve(store: store).report {
            print(Self.line(name: row.editorID, setting: row.setting, units: ""))
        }
    }

    /// The three settings `ArcherySettings` resolves (issue #196), with the
    /// plugin or the UESP-documented fallback each came from.
    private static func runArchery(context: CLIContext) throws {
        let file = try context.loadSkyrimESM()
        let store = GameSettingLoader.load(root: context.root, baseFile: file)
        for row in ArcherySettings.resolve(store: store).report {
            print(Self.line(name: row.editorID, setting: row.setting, units: ""))
        }
    }

    private static func runMovement(context: CLIContext) throws {
        let file = try context.loadSkyrimESM()
        let store = GameSettingLoader.load(root: context.root, baseFile: file)
        let configuration = PlayerMovementConfiguration.resolve(
            store: store,
            movementTypes: MovementTypeLoader.load(root: context.root, baseFile: file)
        )
        for row in [
            (name: "fMoveCharWalkBase", setting: configuration.walkSpeed, units: "units/s"),
            (name: "fMoveCharRunBase", setting: configuration.runSpeed, units: "units/s"),
            (name: "sprintSpeed", setting: configuration.sprintSpeed, units: "units/s"),
            (name: "sneakSpeed", setting: configuration.sneakSpeed, units: "units/s"),
            (name: "swimSpeed", setting: configuration.swimSpeed, units: "units/s"),
            (name: "stepHeight", setting: configuration.stepHeight, units: "units"),
            (
                name: "jumpTakeoffSpeed",
                setting: configuration.jumpTakeoffSpeed,
                units: "units/s"
            )
        ] {
            print(Self.line(name: row.name, setting: row.setting, units: row.units))
        }
    }

    private static func line(name: String, setting: MovementSetting, units: String) -> String {
        String(
            format: "%@ = %.3f %@ [%@]",
            name,
            setting.value,
            units,
            setting.source
        )
    }
}
