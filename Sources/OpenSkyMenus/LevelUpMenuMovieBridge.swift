// The measured AS2 contract of `Interface\levelupmenu.swf`: three buttons that call
// the engine with `addMagicka`, `addHealth`, or `addStamina`. The engine model owns
// the selection; see docs/engine/skills-menu.md.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData

nonisolated public enum LevelUpMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\levelupmenu.swf"
    public static let menuPath = "/LevelUpMenu_mc"
    public static let sinkHostFunctions = ["PlaySound", "myLog"]
    /// The host call each button makes when pressed.
    public static let choiceFunctions: [String: ActorValueKind] = [
        "addHealth": .health, "addMagicka": .magicka, "addStamina": .stamina
    ]

    public static func prepare(
        runtime: SWFMovieRuntime,
        onChoice: @escaping @MainActor @Sendable (ActorValueKind) -> Void
    ) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        for (name, kind) in choiceFunctions {
            runtime.registerHostFunction(name) { _ in
                MainActor.assumeIsolated { onChoice(kind) }
                return .undefined
            }
        }
    }

    /// `InitExtensions` wires the buttons' press listeners.
    public static func activate(runtime: SWFMovieRuntime) {
        runtime.callMovie(
            "SetPlatform", arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        runtime.callMovie("InitExtensions")
    }

    /// Moves the movie's focus to the button of `kind`, which draws its highlight.
    public static func highlight(_ kind: ActorValueKind, runtime: SWFMovieRuntime) {
        runtime.focus(runtime.node(atPath: buttonPath(kind), from: runtime.root))
    }

    public static func buttonPath(_ kind: ActorValueKind) -> String {
        switch kind {
        case .health: "\(menuPath)/HealthButton"
        case .magicka: "\(menuPath)/MagickaButton"
        case .stamina: "\(menuPath)/StaminaButton"
        }
    }

    /// True when the three buttons exist, so the movie can show the choice.
    public static func buttonsBuilt(runtime: SWFMovieRuntime) -> Bool {
        ActorValueKind.allCases.allSatisfy {
            runtime.node(atPath: buttonPath($0), from: runtime.root) != nil
        }
    }
}
