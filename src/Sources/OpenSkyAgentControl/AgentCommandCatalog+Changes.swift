// The catalog entries of the debug commands that change the world as a script or a
// console line would, and the music read.

nonisolated extension AgentCommandCatalog {
    private static let formHelp = "A load-order hex FormID, as the console takes it."
    private static let anyRefHelp =
        "The player, the target under the crosshair, or any reference's hex FormID."

    static let worldChanges: [AgentCommandSpec] = [
        command(
            "debug.imod", "Apply or remove an image space modifier, as ImageSpaceModifier does.",
            positionals: [required("modifier", "The IMAD. " + formHelp)],
            options: [
                value("strength", "x", "Strength, 1 by default."),
                value("fade", "s", "Seconds to fade in, or out with --off. 0 by default."),
                flag("crossfade", "Hold it at full strength until removed, as ApplyCrossFade."),
                flag("off", "Remove the modifier.")
            ]
        ),
        command(
            "debug.cast", "Cast a spell, as Spell.Cast does.",
            positionals: [required("spell", "The SPEL. " + formHelp)],
            options: [
                value("ref", "ref", "The caster. Default: player."),
                value("target", "ref", "The target. Default: none.")
            ]
        ),
        command(
            "debug.spell", "Give an actor a spell or take it away, as AddSpell does.",
            positionals: [
                required("spell", "The SPEL. " + formHelp),
                optional("on", "Either on to give it or off to take it; on by default.")
            ],
            options: [value("ref", "ref", "The actor. Default: player.")]
        ),
        command(
            "debug.enable", "Enable a reference, as ObjectReference.Enable does.",
            positionals: [required("ref", anyRefHelp)]
        ),
        command(
            "debug.disable", "Disable a reference, as ObjectReference.Disable does.",
            positionals: [required("ref", anyRefHelp)]
        ),
        command(
            "debug.decal", "Strike a loaded actor with a blade hit on its side facing you.",
            positionals: [required("ref", "The actor: target or a loaded reference's FormID.")],
            options: [value("height", "units", "Height above the feet; 100 by default.")]
        ),
        command(
            "debug.spawn", "Place a new reference of a base object, as PlaceAtMe does.",
            positionals: [required("base", "The base object. " + formHelp)],
            options: [value("at", "ref", "Where to place it. Default: player.")]
        )
    ]

    static let musicRead: [AgentCommandSpec] = [
        command("state.music", "The playing music type and track, and what interrupts it."),
        command("state.sounds", "The playing sounds, where they play, and the newest ones started.")
    ]
}
