// The player's part of an import: identity and face from the base `NPC_` change, level
// and experience from the header, spells and factions, and the saved place.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

nonisolated extension ESSImporter {
    mutating func importPlayer() {
        let base = playerBase()
        importIdentity(base)
        add(
            PlayerProgressState(
                level: Int(file.header.playerLevel), experience: file.header.experience
            ),
            to: .player
        )
        report.update("player") { category in
            category.imported += 1
            category.skip("perk points, skills, and perks (actor data is undocumented)")
        }
        if let base {
            importSpells(base)
            importFactions(base)
        }
        importPlacement()
    }

    private func playerBase() -> ESSActorBaseChange? {
        let form = file.changeForms.first {
            $0.type?.signature == "NPC_" && $0.form == ESSActorBaseChange.playerBase
        }
        return form.flatMap { try? ESSActorBaseChange($0) }
    }

    private mutating func importIdentity(_ base: ESSActorBaseChange?) {
        let race = base?.race.flatMap { try? form($0, signature: ["RACE"]).get() }
            ?? records.race(editorID: file.header.playerRaceEditorID)
        guard let race, let raceID = mapping.currentFormID(race) else {
            let missing = "race \(file.header.playerRaceEditorID) not found"
            report.update("player") { $0.drop(missing) }
            return
        }
        let identity = PlayerIdentityState(
            race: raceID, isFemale: base?.isFemale ?? file.header.isFemale,
            name: file.header.playerName, face: face(base?.face)
        )
        add(identity, to: .player)
        report.update("player") { category in
            category.imported += 1
            category.skip("face tint layers (not in the save's face block)")
        }
    }

    private func face(_ face: ESSFace?) -> PlayerFace {
        guard let face else { return PlayerFace() }
        return PlayerFace(
            morphs: face.morphs, parts: face.presets,
            headParts: face.headParts.compactMap(currentFormID),
            hairColor: currentFormID(face.hairColor)
        )
    }

    func currentFormID(_ ref: ESSRefID) -> FormID? {
        guard case let .form(form) = mapping.resolve(ref) else { return nil }
        return mapping.currentFormID(form)
    }

    private mutating func importSpells(_ base: ESSActorBaseChange) {
        var known: [ReferenceKey] = []
        for spell in base.spells ?? [] {
            switch form(spell, signature: ["SPEL"]) {
            case let .success(form): known.append(ReferenceKey(resolved: form))
            case let .failure(reason): report
                .update("player") { $0.drop("spell: \(reason.description)") }
            }
        }
        report.update("player") { category in
            category.imported += known.count
            category.drop(
                "shout (OpenSky keeps no known-shout list)",
                count: base.shouts?.count ?? 0
            )
            category.drop("leveled spell", count: base.leveledSpells?.count ?? 0)
        }
        guard !known.isEmpty else { return }
        add(SpellbookState(known: known), to: .player)
    }

    private mutating func importFactions(_ base: ESSActorBaseChange) {
        var memberships: [ActorFactionMembership] = []
        for entry in base.factions ?? [] {
            switch form(entry.faction, signature: ["FACT"]) {
            case let .success(form):
                memberships.append(
                    ActorFactionMembership(faction: ReferenceKey(resolved: form), rank: entry.rank)
                )
            case let .failure(reason):
                report.update("player") { $0.drop("faction: \(reason.description)") }
            }
        }
        report.update("player") { $0.imported += memberships.count }
        guard !memberships.isEmpty else { return }
        add(ActorFactionState(memberships: memberships), to: .player)
    }

    private mutating func importPlacement() {
        guard let location = try? file.playerLocation() else {
            report.update("player") { $0.skip("player location table") }
            return
        }
        switch form(location.space, signature: ["CELL", "WRLD"]) {
        case let .failure(reason):
            report.update("player") { $0.drop("saved place: \(reason.description)") }
        case let .success(space):
            let isInterior = records.signature(of: space) == "CELL"
            placement = ESSImportedPlacement(
                space: space, isInterior: isInterior, spaceEditorID: records.editorID(of: space),
                position: location.position, heading: playerHeading(),
                cell: isInterior ? nil : location.cell
            )
            report.update("player") { $0.imported += 1 }
        }
    }

    private func playerHeading() -> Float? {
        let player = file.changeForms.first {
            $0.form == ESSRefID(kind: .default, value: Self.playerReference.objectID)
                && $0.type?.signature == "ACHR"
        }
        return player.flatMap { try? ESSReferenceChange($0) }?.placement?.rotation.z
    }
}
