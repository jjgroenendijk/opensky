// The catalog entries of the debug commands that change the world as a script or a
// console line would, and the music read.

nonisolated extension AgentCommandCatalog {
    private static let formHelp = "A load-order hex FormID, as the console takes it."
    private static let anyRefHelp =
        "The player, the target under the crosshair, or any reference's hex FormID."

    static let worldChanges: [AgentCommandSpec] = [
        command(
            "debug.imod", "Apply or remove an image space modifier, as ImageSpaceModifier does.",
            positionals: [requiredText("modifier", "The IMAD. " + formHelp)],
            options: [
                value("strength", "x", "Strength, 1 by default."),
                value("fade", "s", "Seconds to fade in, or out with --off. 0 by default."),
                flag("crossfade", "Hold it at full strength until removed, as ApplyCrossFade."),
                flag("off", "Remove the modifier.")
            ]
        ),
        command(
            "debug.cast", "Cast a spell, as Spell.Cast does.",
            positionals: [requiredText("spell", "The SPEL. " + formHelp)],
            options: [
                value("ref", "ref", "The caster. Default: player."),
                value("target", "ref", "The target. Default: none.")
            ]
        ),
        command(
            "debug.spell", "Give an actor a spell or take it away, as AddSpell does.",
            positionals: [
                requiredText("spell", "The SPEL. " + formHelp),
                optional("on", "Either on to give it or off to take it; on by default.")
            ],
            options: [value("ref", "ref", "The actor. Default: player.")]
        ),
        command(
            "debug.enable", "Enable a reference, as ObjectReference.Enable does.",
            positionals: [requiredText("ref", anyRefHelp)]
        ),
        command(
            "debug.disable", "Disable a reference, as ObjectReference.Disable does.",
            positionals: [requiredText("ref", anyRefHelp)]
        ),
        command(
            "debug.delete", "Delete a reference, as ObjectReference.Delete does.",
            positionals: [requiredText("ref", anyRefHelp)]
        ),
        command(
            "debug.lock", "Lock or unlock a reference, as ObjectReference.Lock does.",
            positionals: [
                requiredText("ref", anyRefHelp),
                optional("on", "Either on to lock it or off to unlock it; on by default.")
            ]
        ),
        command(
            "debug.release", "Let a looping sound finish its pass, as a SoundRelease event does.",
            positionals: [required("id", "The sound's id from state sounds.")]
        ),
        command(
            "debug.grab", "Hold a loose object or a dead body as holding Activate does.",
            positionals: [optionalText("ref", "The reference to hold; none lets go.")]
        ),
        command(
            "debug.activate", "Activate a reference, as ObjectReference.Activate does.",
            positionals: [requiredText("ref", anyRefHelp)],
            options: [value("by", "ref", "The activator. Default: player.")]
        ),
        command(
            "debug.decal", "Strike a loaded actor with a blade hit on its side facing you.",
            positionals: [requiredText("ref", "The actor: target or a loaded reference's FormID.")],
            options: [value("height", "units", "Height above the feet; 100 by default.")]
        ),
        command(
            "debug.spawn", "Place a new reference of a base object, as PlaceAtMe does.",
            positionals: [requiredText("base", "The base object. " + formHelp)],
            options: [value("at", "ref", "Where to place it. Default: player.")]
        ),
        command(
            "debug.detectionevent",
            "Make a sound event of the player at the player's feet, for detection.",
            positionals: [required(
                "level",
                "The sound level: 10 silent, 50 normal, 200 very loud."
            )]
        )
    ]

    static let musicRead: [AgentCommandSpec] = [
        command("state.music", "The playing music type and track, and what interrupts it."),
        command("state.sounds", "The playing sounds, where they play, and the newest ones started.")
    ]
}
