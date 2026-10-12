// The measured AS2 contract of `Interface\statsmenu.swf`, the skills menu. The engine
// fills `StatsMenu.SkillStatsA` and `StatsMenu.PerkNamesA` and calls the movie's
// `GameDelegate` callbacks. Vanilla draws the perk stars in 3D outside the movie;
// OpenSky places only the perk names. See docs/engine/skills-menu.md.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyProgressionInterface

nonisolated public enum StatsMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\statsmenu.swf"
    public static let className = "StatsMenu"
    /// Camera moves belong to the 3D sky vanilla draws behind the movie.
    public static let sinkHostFunctions = ["MoveCamera", "SetFadedIn", "PlaySound", "myLog"]
    /// Degrees between two skills on the ring (`SKILL_ANGLE`).
    public static let skillAngle = 20.0
    /// Values per skill in `SkillStatsA`: level, name, meter, colour, legendary count.
    public static let skillStride = 5

    public static func prepare(runtime: SWFMovieRuntime) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
    }

    public static func activate(runtime: SWFMovieRuntime) {
        runtime.callMovie(
            "SetPlatform", arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        runtime.callMovie("InitExtensions")
        runtime.callMovie("ShowLegendaryButtonHint")
    }

    /// The `StatsMenu` class, or nil when the movie did not define it.
    public static func menuClass(runtime: SWFMovieRuntime) -> AS2Object? {
        runtime.runtime.globalValue(className).objectValue
    }

    /// Sends the whole model: the card, the ring, the tree's names, and the mode.
    public static func publish(_ model: SkillsMenuModel, runtime: SWFMovieRuntime) {
        guard let menuClass = menuClass(runtime: runtime) else { return }
        publishPlayer(model.player, runtime: runtime)
        let ring = model.skills.flatMap(skillValues)
        menuClass.assign(.object(runtime.runtime.makeArray(ring)), for: "SkillStatsA")
        runtime.callMovie("UpdateSkillList", arguments: [.boolean(true)])
        runtime.callMovie(
            "SetDirection", arguments: [.number(Double(model.skillPosition) * skillAngle)]
        )
        let inTree = model.page == .perks
        let names = inTree ? model.perks.flatMap { perkValues($0, model: model) } : []
        menuClass.assign(.object(runtime.runtime.makeArray(names)), for: "PerkNamesA")
        runtime.callMovie(
            "SetStatsMode",
            arguments: [.boolean(true), .integer(model.player.perkPoints)]
        )
        publishCard(model, inTree: inTree, runtime: runtime)
        updatePerkText(show: inTree, menuClass: menuClass, runtime: runtime)
    }

    /// `SetPlayerInfo`: name, level, level meter, race, then current, maximum, and
    /// colour for magicka, health, and stamina.
    static func publishPlayer(_ player: SkillsMenuPlayer, runtime: SWFMovieRuntime) {
        let meters = [player.magicka, player.health, player.stamina].flatMap { meter in
            [
                AS2Value.integer(Int(meter.current.rounded())),
                .integer(Int(meter.maximum.rounded())),
                .undefined
            ]
        }
        runtime.callMovie("SetPlayerInfo", arguments: [
            .string(player.name), .integer(player.level),
            .number(Double(player.levelProgress) * 100), .string(player.race)
        ] + meters)
    }

    /// `SetDescriptionCard(perkMode, name, meter, description, requirement, level,
    /// skill, legendaryCount)`.
    static func publishCard(_ model: SkillsMenuModel, inTree: Bool, runtime: SWFMovieRuntime) {
        guard let skill = model.selectedSkill else { return }
        let perk = inTree ? model.selectedPerk : nil
        runtime.callMovie("SetDescriptionCard", arguments: [
            .boolean(perk != nil),
            .string(perk?.name ?? skill.name),
            .number(Double(skill.progress) * 100),
            .string(perk?.description ?? skill.description),
            .string(perk?.requirement ?? ""),
            .integer(Int(skill.level)),
            .string(skill.name),
            .integer(skill.legendaryCount)
        ])
    }

    static func skillValues(_ skill: SkillsMenuSkill) -> [AS2Value] {
        [
            .integer(Int(skill.level)), .string(skill.name), .number(Double(skill.progress) * 100),
            .undefined, .integer(skill.legendaryCount)
        ]
    }

    /// One name per box, as `[html, x, y]` on a 0 to 1 stage. The tree grows up from
    /// the bottom centre; owned boxes are white and the selected one is bold.
    static func perkValues(_ perk: SkillsMenuPerk, model: SkillsMenuModel) -> [AS2Value] {
        let colour = perk.isOwned ? "#FFFFFF" : "#8C8C8C"
        var text = "<font color='\(colour)'>\(escaped(perk.name))</font>"
        if perk.node == model.selectedPerk?.node {
            text = "<b>\(text)</b>"
        }
        let x = 0.5 + (Double(perk.gridX) - 2) * 0.12
        let y = 0.85 - Double(perk.gridY) * 0.11
        return [.string(text), .number(min(0.95, max(0.05, x))), .number(min(0.95, max(0.05, y)))]
    }

    /// `UpdatePerkText(show)` is a method of the menu instance, not a callback.
    static func updatePerkText(show: Bool, menuClass: AS2Object, runtime: SWFMovieRuntime) {
        guard let instance = menuClass.lookup("StatsMenuInstance")?.property.value.objectValue
        else { return }
        let method = instance.lookup("UpdatePerkText")?.property.value ?? .undefined
        runtime.runtime.invoke(method, thisValue: .object(instance), arguments: [.boolean(show)])
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
