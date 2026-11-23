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
            options: [
                value("radius", "units", "Search radius in game units. Default: 4096."),
                value("detailed", "count", "Nearest actors that get a full row. Default: 8.")
            ]
        ),
        command("state.menu", "The open menus and the selected rows."),
        command(
            "state.quest", "A quest's stage, objectives, and aliases.",
            positionals: [required("id", "The quest editor ID.")]
        ),
        command("state.scenes", "Each playing scene with its quest and phase."),
        command("state.story", "The story-manager events fired, by code, and the newest ones."),
        command("state.social", "NPC conversations, walks, fight watchers, and checked bodies."),
        command("state.stats", "The journal's misc stats counted so far, by name."),
        command(
            "state.projectiles",
            "The shots in the air, the arrows standing, and how the newest shots ended."
        ),
        command(
            "state.assist",
            "Attack tracking, auto-aim, dodges, hit reactions, and AI process levels."
        ),
        command(
            "state.scripts", "The script queue, waits, events, faults, and missing natives.",
            positionals: [optionalText("ref", "Also list the scripts on this reference or quest.")]
        ),
        command(
            "state.packages", "An actor's package, procedure, and mover state.",
            positionals: [requiredText("ref", refHelp)]
        ),
        command(
            "state.furniture", "An actor's seat, or a piece of furniture's markers.",
            positionals: [optionalText("ref", "Default: player.")]
        ),
        command(
            "state.flight", "Each actor in the air, or one actor's flight, and the ridden dragon.",
            positionals: [optionalText("ref", refHelp)]
        ),
        command(
            "state.mount", "The player's mount: kind, phase, motion, and a dragon's orders."
        ),
        command("state.cloth", "The cape cloth switch and the capes stepped last frame."),
        command("state.grab", "The grab switch, the Activate phase, and what the player holds."),
        command(
            "state.paired",
            "Each paired animation playing: its idle, and each actor's role and paired clips."
        ),
        command(
            "state.impulses",
            "Hit knockback, explosion push, and splash settings, with the newest events."
        ),
        command(
            "state.alarm",
            "Each alarm witness and its role, the fights, and the theft mark."
        ),
        command(
            "state.favor",
            "Follower command mode: the phase, follower, last decision, and last outcome."
        ),
        command(
            "state.objects", "Each running object graph; with a reference, also its bones.",
            positionals: [optionalText("ref", refHelp)]
        ),
        command(
            "state.effects",
            "Each running effect or armour addon graph: its actor, state, and last event.",
            positionals: [optionalText("ref", "Only the sub-graphs on this actor.")]
        ),
        command(
            "state.nodes",
            "Placed meshes playing node controllers, or the nodes of one.",
            positionals: [optionalText("ref", refHelp)]
        ),
        command(
            "state.changes", "The newest world-state writes and any rebuild in flight.",
            options: [value("limit", "n", "Writes to list. Default: 20.")]
        ),
        command(
            "state.av", "One actor value: base, current, and modifiers.",
            positionals: [requiredText("name", "The actor value, such as Health.")],
            options: [value("ref", "ref", "The actor. Default: player.")]
        ),
        command(
            "state.global", "A global variable's value.",
            positionals: [required("id", "The global editor ID.")]
        ),
        command(
            "state.condition", "What one condition function returns now, run on a reference.",
            positionals: [
                requiredText("function", "The function's Creation Kit name, such as GetLocked.")
            ],
            options: [
                value("ref", "ref", "The reference it runs on. Default: player."),
                value("param", "value", "The first parameter: a hex FormID or a number."),
                value("param2", "value", "The second parameter: a hex FormID or a number."),
                value(
                    "target", "ref",
                    "The other reference, which a function with no reference parameter reads."
                )
            ]
        ),
        command("state.time", "The game clock."),
        command("state.frame", "The frame counter and the timeline."),
        command(
            "state.view",
            "The view for the reference game: feet, angles, place, hour, and weather."
        ),
        command("state.newgame", "The last new game started at a chosen place.")
    ]

    static let debug: [AgentCommandSpec] =
        teleportAndTime + actorChanges + menusAndRender + worldChanges

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
            "debug.newgame", "Start a new game at a place, as the launcher's Play does.",
            options: [
                value(
                    "at",
                    "start",
                    "A start: cell:EditorID, exterior:World:X:Y, or marker:World:Plugin:ID."
                ),
                value("hour", "h", "The hour of the day, 0 to 24. Default: the new game hour."),
                value("weather", "editorID", "Force this weather on arrival."),
                value("story", "state", "One of not-started, helgen-hadvar, helgen-ralof."),
                value("items", "preset", "One of none, warrior, archer, mage, thief."),
                negatedFlag("racemenu", "Do not open the race menu on arrival.")
            ]
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
            positionals: [requiredText("name", "The actor value, such as Health.")],
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
                flag("equip", "Then equip it on the player."),
                flag("left", "Then equip it in the player's left hand: a one-handed weapon.")
            ]
        ),
        command(
            "debug.quest", "Set a quest stage.",
            positionals: [required("id", "The quest editor ID."), required("stage", "The stage.")]
        ),
        command("debug.kill", "Kill an actor.", positionals: [requiredText("ref", refHelp)]),
        command(
            "debug.resurrect",
            "Resurrect an actor.",
            positionals: [requiredText("ref", refHelp)]
        ),
        command(
            "debug.decapitate", "Cut a dead actor's head off, as a severing killing blow does.",
            positionals: [requiredText("ref", refHelp)]
        ),
        command(
            "debug.subgraph", "Send an event or set a variable on an actor's sub-graphs.",
            positionals: [requiredText("ref", refHelp)],
            options: [
                value("event", "name", "The event, as PlaySubGraphAnimation sends it."),
                value("var", "name", "The variable, as SetSubGraphFloatVariable sets it."),
                value("value", "v", "The variable's new value.")
            ]
        ),
        command(
            "debug.sit", "Seat an actor in furniture.",
            positionals: [optionalText("ref", "The actor. Default: player.")],
            options: [value("furniture", "ref", "Default: the nearest loaded free seat.")]
        ),
        command(
            "debug.stand", "Get an actor up from its seat.",
            positionals: [optionalText("ref", "The actor. Default: player.")]
        ),
        command(
            "debug.favor", "Put a follower in command mode, as its do-something topic does.",
            positionals: [requiredText("ref", refHelp)],
            options: [
                value("target", "ref", "Then command it to use this reference, or go to x,y,z."),
                flag("exit", "Leave command mode instead, as the pause key does.")
            ]
        ),
        command(
            "debug.teammate", "Make an actor a player teammate, as SetPlayerTeammate does.",
            positionals: [requiredText("ref", refHelp)],
            options: [flag("off", "Clear the teammate flag instead.")]
        ),
        command(
            "debug.relationship",
            "Set an actor's relationship rank toward the player, as SetRelationshipRank does.",
            positionals: [
                requiredText("ref", refHelp),
                required("rank", "The rank, from -4 (Archnemesis) to 4 (Lover).")
            ]
        ),
        command(
            "debug.flight", "Force an actor that flies to take off, land, or perch.",
            positionals: [
                requiredText("ref", refHelp),
                requiredText("order", "One of takeoff, land, perch, hasty, or crash.")
            ]
        ),
        command(
            "debug.sound", "Mute or unmute the game's sound.",
            positionals: [required("on", "Either on or off.")]
        ),
        command(
            "debug.setting", "Apply player settings over the saved ones until the next call.",
            positionals: [optionalText(
                "values",
                "Comma-separated id=value pairs; none restores them."
            )]
        ),
        command(
            "debug.drunk", "Start or stop an actor's drunk state, as IdleDrunkStart does.",
            positionals: [requiredText("ref", refHelp), required("on", "Either on or off.")]
        ),
        command(
            "debug.paired", "Play an idle with a target, as PlayIdleWithTarget does.",
            positionals: [
                requiredText("ref", refHelp),
                required("target", "The actor that plays the other half of a paired idle."),
                requiredText("idle", "The IDLE editor ID, such as 1HMKillMoveC.")
            ]
        ),
        command(
            "debug.translate", "Move a reference over time, as TranslateTo does.",
            positionals: [
                requiredText("ref", refHelp),
                required("to", "The target position as x,y,z; the rotation stays."),
                optional("speed", "Units a second; 100 by default.")
            ]
        ),
        command(
            "debug.knock", "Knock an actor back as a melee hit from the player would.",
            positionals: [
                requiredText("ref", refHelp),
                required("damage", "The hit's damage; a killing hit does not knock.")
            ]
        ),
        command(
            "debug.knockdown", "Knock an actor down as a ragdoll, away from the player.",
            positionals: [
                requiredText("ref", refHelp),
                optional("magnitude", "Havok metres a second; 10 by default, negative pulls.")
            ]
        ),
        command(
            "debug.perk", "Give the player a perk or take it away, as Actor.AddPerk does.",
            positionals: [
                requiredText("perk", "The perk's editor ID, such as ShieldCharge."),
                optional("on", "Either on to give it or off to take it; on by default.")
            ]
        ),
        command(
            "debug.form", "Put the player in a beast form, or end it.",
            positionals: [requiredText("form", "One of werewolf, vampirelord, or none.")]
        ),
        command(
            "debug.link",
            "Hold two ragdolls' bones together, as AddHavokBallAndSocketConstraint does.",
            positionals: [
                requiredText("ref", refHelp), requiredText(
                    "node",
                    "The bone of the first ragdoll."
                ),
                requiredText("other", "The second actor, as ref takes it."),
                requiredText("othernode", "The bone of the second ragdoll."),
                optional("on", "Either on to link or off to unlink; on by default.")
            ]
        ),
        command(
            "debug.eyes", "Draw an actor's eyes with a texture set, as SetEyeTexture does.",
            positionals: [
                requiredText("ref", refHelp), requiredText("set", "The TXST, as a hex FormID.")
            ]
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
                requiredText(
                    "name",
                    "One of navmesh, path, detection, hud, ui, or a render layer."
                ),
                required("on", "Either on or off.")
            ]
        ),
        command(
            "debug.channel", "Show one debug channel of the scene pass.",
            positionals: [requiredText(
                "mode",
                "One of off, wireframe, worldnormals, miplevel, and more."
            )]
        ),
        command(
            "debug.shadows", "Set the sun shadow tier until the renderer is rebuilt.",
            positionals: [requiredText("quality", "One of off, low, or high.")]
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
            "debug.loadscreen", "Hold a loading screen on screen until it is released.",
            positionals: [optional("id", "The LSCR editor ID; none releases the held screen.")]
        ),
        command(
            "debug.fasttravel",
            "Fast travel to a map marker, as the map does, without its refusals.",
            positionals: [requiredText("marker", "The map marker's name, such as Riverwood.")]
        ),
        command(
            "debug.playbink", "Play a Bink movie from Data/Video, as Game.PlayBink does.",
            positionals: [requiredText("file", "The movie file, such as BGS_Logo.bik.")],
            options: [flag("interruptible", "Let a key skip the movie.")]
        ),
        command("debug.skipbink", "End the playing movie, even one a key cannot skip."),
        command(
            "debug.titles", "Show or hide the opening titles, or play one, as MQ101 does.",
            positionals: [requiredText("step", "Either show, hide, or a clip such as Sequence1.")]
        )
    ]
}
