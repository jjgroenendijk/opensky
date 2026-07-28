// `gmst movement`: read-only resolution report for controller tuning. Source
// names make both winning plugin overrides and explicit fallbacks inspectable.

import Foundation

enum GMSTCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let subject = try scanner.positional("subject")
        try scanner.finish()
        guard subject == "movement" else {
            throw CLIError.usage("unknown gmst subject: \(subject)")
        }
        let file = try context.loadSkyrimESM()
        let store = GameSettingLoader.load(root: context.root, baseFile: file)
        let configuration = PlayerMovementConfiguration.resolve(store: store)
        print(Self.line(
            name: "fMoveCharWalkBase",
            setting: configuration.walkSpeed,
            units: "units/s"
        ))
        print(Self.line(
            name: "fMoveCharRunBase",
            setting: configuration.runSpeed,
            units: "units/s"
        ))
        print(Self.line(
            name: "stepHeight",
            setting: configuration.stepHeight,
            units: "units"
        ))
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
