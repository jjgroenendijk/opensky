// The `state` reads and `debug` changes of the command catalog.

import Foundation

nonisolated extension AgentCommandCatalog {
    private static let refHelp =
        "The player, the target under the crosshair, or a loaded reference's hex FormID."

    static let state: [AgentCommandSpec] = [
        command("state.player", "The player: position, cell, worldspace, weather, level, spells."),
        command("state.target", "The reference under the crosshair."),
        command(
            "state.actors",
            "Loaded actors near the player, with their leveled rolls and behaviour graphs.",
            options: [value("radius", "units", "Search radius in game units. Default: 4096.")]
        ),
        command("state.menu", "The open menus and the selected rows."),
        command(
            "state.quest", "A quest's stage, objectives, and aliases.",
            positionals: [required("id", "The quest editor ID.")]
        ),
        command("state.scenes", "Each playing scene with its quest and phase."),
        command(
            "state.scripts", "The script queue, waits, events, faults, and missing natives.",
            positionals: [optional("ref", "Also list the scripts on this reference or quest.")]
        ),
        command(
            "state.packages", "An actor's package, procedure, and mover state.",
            positionals: [required("ref", refHelp)]
        ),
        command(
            "state.furniture", "An actor's seat, or a piece of furniture's markers.",
            positionals: [optional("ref", "Default: player.")]
        ),
        command(
            "state.flight", "Each actor in the air, or one actor's flight, and the ridden dragon.",
            positionals: [optional("ref", refHelp)]
        ),
        command(
            "state.mount", "The player's mount: kind, phase, motion, and a dragon's orders."
        ),
        command(
            "state.objects", "Each running object graph; with a reference, also its bones.",
            positionals: [optional("ref", refHelp)]
        ),
        command(
            "state.effects",
            "Each running effect or armour addon graph: its actor, state, and last event.",
            positionals: [optional("ref", "Only the sub-graphs on this actor.")]
        ),
        command(
            "state.nodes",
            "Placed meshes playing node controllers, or the nodes of one.",
            positionals: [optional("ref", refHelp)]
        ),
        command(
            "state.changes", "The newest world-state writes and any rebuild in flight.",
            options: [value("limit", "n", "Writes to list. Default: 20.")]
        ),
        command(
            "state.av", "One actor value: base, current, and modifiers.",
            positionals: [required("name", "The actor value, such as Health.")],
            options: [value("ref", "ref", "The actor. Default: player.")]
        ),
        command(
            "state.global", "A global variable's value.",
            positionals: [required("id", "The global editor ID.")]
        ),
        command("state.time", "The game clock."),
        command("state.frame", "The frame counter and the timeline."),
        command(
            "state.view",
            "The view for the reference game: feet, angles, place, hour, and weather."
        )
    ]

    static let debug: [AgentCommandSpec] = teleportAndTime + actorChanges + menusAndRender

    private static let teleportAndTime: [AgentCommandSpec] = [
        command(
            "debug.teleport", "Move the player. Give --cell, --ref, --pos, or --x and --y.",
            options: [
                value("cell", "editorID", "Any cell in the load order."),
                value("ref", "ref", "Next to a placed reference."),
                value("pos", "x,y,z", "A position in the current cell or worldspace."),
                value("x", "n", "Exterior cell grid X."),
                value("y", "n", "Exterior cell grid Y."),
                value("worldspace", "editorID", "Go to this worldspace first.")
            ]
        ),
        command(
            "debug.view", "Put the player at a view: place, facing, hour, and weather.",
            options: [
                value("pos", "x,y,z", "The feet, in the cell's space for an interior."),
                value("yaw", "deg", "0 looks east (+X); turns towards north."),
                value("pitch", "deg", "Up is positive. Default: 0."),
                value("worldspace", "editorID", "The exterior worldspace."),
                value("interior", "formID", "The interior cell, instead of a worldspace."),
                value("hour", "h", "0 to 24."),
                value("weather", "formID", "Force this weather at once.")
            ]
        ),
        command(
            "debug.time", "Set the hour of the day.",
            positionals: [required("hour", "0 to 24, such as 13.5.")]
        ),
        command(
            "debug.weather", "Force a weather; no ID clears it.",
            positionals: [optional("id", "The weather editor ID.")]
        ),
        command(
            "debug.rest", "Pass hours as the wait menu does, without the refusals.",
            positionals: [required("hours", "1 to 24.")],
            options: [flag("sleep", "Pass them as the rest menu does.")]
        )
    ]

    private static let actorChanges: [AgentCommandSpec] = [
        command(
            "debug.av", "Set or change an actor value. Give --value or --mod.",
            positionals: [required("name", "The actor value, such as Health.")],
            options: [
                value("value", "v", "The new base value."),
                value("mod", "d", "Add this to the current value."),
                value("ref", "ref", "The actor. Default: player.")
            ]
        ),
        command(
            "debug.item", "Add an item to the player, or remove it with a negative count.",
            positionals: [required("id", "The item editor ID.")],
            options: [
                value("count", "n", "Default: 1."),
                value("ref", "ref", "The container. Default: player."),
                flag("equip", "Then equip it on the player.")
            ]
        ),
        command(
            "debug.quest", "Set a quest stage.",
            positionals: [required("id", "The quest editor ID."), required("stage", "The stage.")]
        ),
        command("debug.kill", "Kill an actor.", positionals: [required("ref", refHelp)]),
        command("debug.resurrect", "Resurrect an actor.", positionals: [required("ref", refHelp)]),
        command(
            "debug.subgraph", "Send an event or set a variable on an actor's sub-graphs.",
            positionals: [required("ref", refHelp)],
            options: [
                value("event", "name", "The event, as PlaySubGraphAnimation sends it."),
                value("var", "name", "The variable, as SetSubGraphFloatVariable sets it."),
                value("value", "v", "The variable's new value.")
            ]
        ),
        command(
            "debug.sit", "Seat an actor in furniture.",
            positionals: [optional("ref", "The actor. Default: player.")],
            options: [value("furniture", "ref", "Default: the nearest loaded free seat.")]
        ),
        command(
            "debug.stand", "Get an actor up from its seat.",
            positionals: [optional("ref", "The actor. Default: player.")]
        ),
        command(
            "debug.flight", "Force an actor that flies to take off, land, or perch.",
            positionals: [
                required("ref", refHelp),
                required("order", "One of takeoff, land, perch, hasty, or crash.")
            ]
        ),
        command(
            "debug.drunk", "Start or stop an actor's drunk state, as IdleDrunkStart does.",
            positionals: [required("ref", refHelp), required("on", "Either on or off.")]
        ),
        command(
            "debug.form", "Put the player in a beast form, or end it.",
            positionals: [required("form", "One of werewolf, vampirelord, or none.")]
        )
    ]

    private static let menusAndRender: [AgentCommandSpec] = [
        command(
            "debug.gamepad", "Report gamepads to the menus, or press gamepad buttons.",
            options: [
                value("count", "n", "Gamepads to report when fewer are connected, 0 to 3."),
                value("press", "buttons", "Buttons to press, such as down,a: a, b, x, y, up.")
            ]
        ),
        command(
            "debug.racemenu", "Open the race menu, as the console's ShowRaceMenu.",
            options: [flag("limited", "Open it as Game.ShowLimitedRaceMenu.")]
        ),
        command(
            "debug.skillsmenu", "Open the skills menu as the Quick Stats key does.",
            options: [
                toggle("sky", "Turn the perk sky on or off."),
                value("levelup", "n", "First earn 1 to 10 character levels.")
            ]
        ),
        command(
            "debug.overlay", "Turn a debug overlay or render layer on or off.",
            positionals: [
                required("name", "One of navmesh, path, detection, hud, ui, or a render layer."),
                required("on", "Either on or off.")
            ]
        ),
        command(
            "debug.channel", "Show one debug channel of the scene pass.",
            positionals: [required(
                "mode",
                "One of off, wireframe, worldnormals, miplevel, and more."
            )]
        ),
        command(
            "debug.shadows", "Set the sun shadow tier until the renderer is rebuilt.",
            positionals: [required("quality", "One of off, low, or high.")]
        ),
        command(
            "debug.fade", "Fade the screen as Papyrus Game.FadeOutGame does.",
            positionals: [required("direction", "Either out or in.")],
            options: [
                flag("white", "Fade to white instead of black."),
                value("delay", "s", "Seconds to wait before the fade."),
                value("duration", "s", "Seconds the fade takes.")
            ]
        ),
        command(
            "debug.cartmode", "Hide the HUD for a cart ride, as Game.SetHudCartMode does.",
            positionals: [required("on", "Either on or off.")]
        ),
        command(
            "debug.playbink", "Play a Bink movie from Data/Video, as Game.PlayBink does.",
            positionals: [required("file", "The movie file, such as BGS_Logo.bik.")],
            options: [flag("interruptible", "Let a key skip the movie.")]
        ),
        command("debug.skipbink", "End the playing movie, even one a key cannot skip."),
        command(
            "debug.titles", "Show or hide the opening titles, or play one, as MQ101 does.",
            positionals: [required("step", "Either show, hide, or a clip such as Sequence1.")]
        )
    ]
}
